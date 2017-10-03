class Kor::Import::ErlangenCrm

  def run
    Relation.transaction do
      Kind.transaction do
        process
        raise ActiveRecord::Rollback
      end
    end
  end

  def process
    doc = crm
    parent_map = {}
    doc.xpath('/rdf:RDF/owl:Class').each do |klass|
      kind = Kind.create(
        url: klass['rdf:about'],
        name: klass.xpath('rdfs:label').text,
        plural_name: klass.xpath('rdfs:label').text.gsub(/E\d+\s/, '').pluralize,
        description: (
          klass.xpath('rdfs:label').text + "\n\n" + 
          klass.xpath('rdfs:comment').text 
        ),
        abstract: true
      )

      unless kind.valid?
        p kind.errors.full_messages
        binding.pry
      end

      if parent = klass.xpath('rdfs:subClassOf/owl:Class').first
        parent_map[kind.url] ||= []
        parent_map[kind.url] << parent['rdf:about']
      end

      klass.xpath('rdfs:subClassOf[@rdf:resource]/@rdf:resource').each do |parent|
        parent_map[kind.url] ||= []
        parent_map[kind.url] << parent.text
      end
    end

    parent_map.each do |child_url, parent_urls|
      parent_urls.each do |parent_url|
        if parent = Kind.where(url: parent_url).first
          if child = Kind.where(url: child_url).first
            parent.children << child
          end
        end
      end
    end

    lookup = {}
    properties.each do |property|
      begin
        url = property['rdf:about']
        lookup[url] = {
          type: property.name,
          url: url,
          name: property.xpath('rdfs:label').text,
          reverse_url: property.xpath('owl:inverseOf/*').map{|r| r['rdf:about']}.first,
          parent_urls: property.xpath('rdfs:subPropertyOf/*').map{|sp| sp['rdf:about']},
          from_urls: property.xpath('rdfs:domain').map{|d| d['rdf:resource']},
          to_urls: property.xpath('rdfs:range').map{|d| d['rdf:resource']},
          description: property.xpath('rdfs:comment').text
        }
      rescue => e
        puts e.message
        puts e.backtrace
        binding.pry
      end
    end

    lookup.each do |url, r|
      if r[:reverse_url] && !lookup[r[:reverse_url]][:reverse_url]
        lookup[r[:reverse_url]][:reverse_url] = url
      end

      if r[:type] == 'SymmetricProperty'
        r[:reverse_url] = url
      end
    end

    done = {}
    relations = []
    lookup.each do |url, r|
      if !done[url] && !done[r[:reverse_url]]
        done[url] = true
        done[r[:reverse_url]] = true

        if r[:reverse_url] && r[:name].present?
          froms = Kind.where(url: r[:from_urls]).pluck(:id)
          tos = Kind.where(url: r[:to_urls]).pluck(:id)

          froms.product(tos).each do |c|
            relation = Relation.create(
              url: url,
              name: r[:name],
              reverse_name: lookup[r[:reverse_url]][:name],
              from_kind_id: c[0],
              to_kind_id: c[1],
              description: r[:description],
              abstract: true
            )
            relation.save!
            relations << relation
          end
        end
      end
    end

    Relation.all.each do |relation|
      if relation.url
        if r = lookup[relation.url]
          if r[:parent_urls].present?
            relation.update_attributes(
              parent_ids: Relation.where(url: r[:parent_urls]).pluck(:id)
            )
          end
        end
      end
    end
  end


  protected

    def properties(base = nil)
      conds = [
        "self::owl:ObjectProperty",
        "self::owl:TransitiveProperty",
        "self::owl:SymmetricProperty",
        # "self::owl:DatatypeProperty",
        "self::owl:FunctionalProperty",
        "self::owl:InverseFunctionalProperty"
      ].join(' or ')
      crm.xpath("/rdf:RDF/*[#{conds}]")
    end

    def crm
      @crm ||= begin
        url = 'http://erlangen-crm.org/ontology/ecrm/ecrm_current.owl'
        response = HTTPClient.new.get(url)
        if response.status == 200
          Nokogiri::XML(response.body)
        else
          raise "request failed: GET #{url} (#{response.status} #{response.body})"
        end
      end
    end

    # TODO: remove this!
    def crm
      @crm ||= Nokogiri::XML(File.read '/home/schepp/Desktop/ecrm_current.owl')
    end

end