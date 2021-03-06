module DataHelper

  # TODO: remove this and instead use current_user(...) from below
  def fake_authentication(options = {})
    options.reverse_merge!(:persist => false)
    
    if options[:persist]
      test_data_for_auth
      options[:user] ||= User.admin
    end
    
    session[:user_id] = options[:user].id
    session[:expires_at] = Kor.session_expiry_time
  end

  def test_data(options = {})
    options.reverse_merge!(
      :groups => false,
      :config => false
    )
    
    test_data_for_auth
    test_kinds
    test_relations
    test_entities
    
    if options[:groups]
      FactoryGirl.create :authority_group
    end
  end

  def test_data_for_auth
    @admins = FactoryGirl.create :admins
    @main = FactoryGirl.create :default
    Kor::Auth.policies.each do |policy|
      Grant.create!(:collection => @main, :credential => @admins, :policy => policy)
    end
    @admin = FactoryGirl.create :admin, :groups => Credential.all
  end
  
  def test_relations
    FactoryGirl.create :has_created,
      :from_kind_id => @person_kind.id, :to_kind_id => @artwork_kind.id
    FactoryGirl.create :is_equivalent_to,
      :from_kind_id => @artwork_kind.id, :to_kind_id => @artwork_kind.id
    FactoryGirl.create :is_located_at,
      :from_kind_id => @artwork_kind.id, :to_kind_id => @location_kind.id
    FactoryGirl.create :shows,
      :from_kind_id => @medium_kind.id, :to_kind_id => @artwork_kind.id
  end
  
  def test_kinds
    @medium_kind = FactoryGirl.create :media
    @person_kind = FactoryGirl.create :people
    @artwork_kind = FactoryGirl.create :works
    @institution_kind = FactoryGirl.create :institutions
    @location_kind = FactoryGirl.create :locations
    @literature_kind = FactoryGirl.create :literatures
  end

  def test_entities  
    @mona_lisa = FactoryGirl.create :mona_lisa, :datings => [FactoryGirl.build(:d1533)]
  end
  
  def default_setup(options = {})
    options.reverse_merge!(
      pictures: false,
      relationships: false
    )

    @default = FactoryGirl.create :default
    @priv = FactoryGirl.create :private

    @media = FactoryGirl.create :media
    @people = FactoryGirl.create :people
    @works = FactoryGirl.create :works

    FactoryGirl.create :has_created, from_kind_id: @people.id, to_kind_id: @works.id
    FactoryGirl.create :shows, from_kind_id: @media.id, to_kind_id: @works.id

    @leonardo = FactoryGirl.create :leonardo
    @mona_lisa = FactoryGirl.create :mona_lisa
    @last_supper = FactoryGirl.create :the_last_supper, collection: @priv

    if options[:relationships]
      Relationship.relate_and_save(@leonardo, 'has created', @mona_lisa)
      Relationship.relate_and_save(@leonardo, 'has created', @last_supper)
    end

    if options[:pictures]
      @picture = FactoryGirl.create :picture_a

      if options[:relationships]
        Relationship.relate_and_save(@picture, 'shows', @mona_lisa)
      end
    end

    @admins = FactoryGirl.create :admins
    @students = FactoryGirl.create :students

    @admin = FactoryGirl.create :admin, groups: [@admins]
    @jdoe = FactoryGirl.create :jdoe, :groups => [@students]
    
    Kor::Auth.grant @default, :all, :to => @admins
    Kor::Auth.grant @default, :view, :to => @students
    Kor::Auth.grant @priv, :all, :to => @admins
  end

  def current_user(user)
    @current_user = user

    @current_user_mock ||= begin
      allow_any_instance_of(ApplicationController).to(
        receive(:current_user).and_return(@current_user)
      )

      allow_any_instance_of(ApplicationController).to(
        receive(:session_expired?).and_return(false)
      )

      true
    end
  end

end
