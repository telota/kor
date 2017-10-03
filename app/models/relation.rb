class Relation < ActiveRecord::Base
  acts_as_paranoid

  has_many :relationships, :dependent => :destroy

  has_many :relation_parent_inheritances, class_name: 'RelationInheritance', foreign_key: :child_id, dependent: :destroy
  has_many :relation_child_inheritances, class_name: 'RelationInheritance', foreign_key: :parent_id, dependent: :destroy
  has_many :parents, through: :relation_parent_inheritances
  has_many :children, through: :relation_child_inheritances
  belongs_to :from_kind, class_name: "Kind"
  belongs_to :to_kind, class_name: "Kind"
  
  validates :reverse_name,
    :presence => true,
    :white_space => true
  validates :name,
    :presence => true,
    :white_space => true
  validates :from_kind_id, :to_kind_id,
    :presence => true

  validate do |relation|
    to_check = relation.parents.to_a
    cycle = false
    while (r = to_check.pop) && !cycle
      if r.id == relation.id
        cycle = true
      else
        to_check += r.parents.to_a
      end
    end

    if cycle
      relation.errors.add :parent_ids, :would_result_in_cycle
    end
  end

  validate do |relation|
    # collection possible endpoints from all parents
    required_from_ids = nil
    required_to_ids = nil
    relation.parents.each do |parent|
      from_ids = [parent.from_kind_id] + parent.from_kind.deep_child_ids
      required_from_ids ||= from_ids
      required_from_ids &= from_ids
      to_ids = [parent.to_kind_id] + parent.to_kind.deep_child_ids
      required_to_ids ||= to_ids
      required_to_ids &= to_ids
    end

    if required_from_ids.is_a?(Array)
      enabled_from_ids = [relation.from_kind_id] + relation.from_kind.deep_child_ids
      # puts 'fROM'
      # p required_from_ids
      # p enabled_from_ids
      subset = ((required_from_ids & enabled_from_ids).size == enabled_from_ids.size)
      unless subset
        relation.errors.add :from_kind_id, :cannot_restrict_less_than_parent
      end
    end

    if required_to_ids.is_a?(Array)
      enabled_to_ids = [relation.to_kind_id] + relation.to_kind.deep_child_ids
      # puts 'TO'
      # p required_to_ids
      # p enabled_to_ids
      subset = ((required_to_ids & enabled_to_ids).size == enabled_to_ids.size)
      unless subset
        relation.errors.add :to_kind_id, :cannot_restrict_less_than_parent
      end
    end
  end

  after_validation :generate_uuid, :on => :create
  after_save :correct_directed

  def parent_ids
    relation_parent_inheritances.pluck(:parent_id)
  end

  def parent_ids=(values)
    self.parents = Relation.where(id: values).to_a
  end

  def child_ids
    relation_child_inheritances.pluck(:child_id)
  end

  def child_ids=(values)
    self.children = Relation.where(id: values).to_a
  end

  def removable(cache = {})
    child_ids.empty? && relationship_count(cache) == 0
  end

  def relationship_count(cache = {})
    relationships.count
  end

  def correct_directed
    if name_changed?
      DirectedRelationship.
        where(is_reverse: false).
        where(relation_id: id).
        update_all(relation_name: name)
    end

    if reverse_name_changed?
      DirectedRelationship.
        where(is_reverse: true).
        where(relation_id: id).
        update_all(relation_name: reverse_name)
    end
  end

  def generate_uuid
    self[:uuid] ||= SecureRandom.uuid
  end

  scope :updated_after, lambda {|time| time.present? ? where("updated_at >= ?", time) : all}
  scope :updated_before, lambda {|time| time.present? ? where("updated_at <= ?", time) : all}
  scope :allowed, lambda {|user, policies| all}
  scope :by_from, lambda {|ids|
    if ids.blank?
      all
    else
      ids = [ids] unless ids.is_a?(Array)
      where(from_kind_id: ids.map{|i| i.to_i})
    end
  }
  scope :by_to, lambda {|ids|
    if ids.blank?
      all
    else
      ids = [ids] unless ids.is_a?(Array)
      where(to_kind_id: ids.map{|i| i.to_i})
    end
  }
  scope :pageit, lambda { |page, per_page|
    page = (page || 1) - 1
    per_page = [(per_page || 30).to_i, Kor.config['app']['max_results_per_request']].min
    limit(per_page).offset(per_page * page)
  }
  default_scope lambda { order(:name) }
  
  def self.available_relation_names(options = {})
    names = by_from(options[:from_ids]).by_to(options[:to_ids]).map{|r| r.name}
    reverse_names = by_from(options[:to_ids]).by_to(options[:from_ids]).map{|r| r.reverse_name}

    (names + reverse_names).sort.uniq
  end

  def self.primary_relation_names
    Kor.config['app.gallery.primary_relations'] || []
  end
  
  def self.secondary_relation_names
    Kor.config['app.gallery.secondary_relations'] || []
  end

  def self.reverse_primary_relation_names
    primary_relation_names.map{|rn| reverse_name_for_name(rn)}
  end
  
  def self.reverse_secondary_relation_names
    secondary_relation_names.map{|rn| reverse_name_for_name(rn)}
  end 

  def self.reverse_name_for_name(name)
    result ||= {}
    return result[name] if result[name]
  
    relation = find_by_name( name )
    return (result[name] = relation.reverse_name) if relation

    relation = find_by_reverse_name( name )
    return (result[name] = relation.name) if relation
  end

end
