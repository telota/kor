require 'rails_helper'

RSpec.describe UserGroupsController, :type => :controller do
  include DataHelper
  
  before :each do
    test_data
  
    session[:user_id] = User.admin.id
    session[:expires_at] = Kor.session_expiry_time
  end
  
  it "should show GET '/user_groups/1'" do
    user_group = FactoryGirl.create :user_group
    
    get :show, :id => user_group.id
    expect(response).to be_success
  end

  it 'should put all entities within a group into the clipboard' do
    leonardo = FactoryGirl.create :leonardo
    mona_lisa = Entity.find_by name: 'Mona Lisa'

    admin = User.admin
    allow_any_instance_of(AuthorityGroupsController).to receive(:current_user).and_return(admin)
    group = FactoryGirl.create :user_group, user_id: admin.id
    group.add_entities [mona_lisa, leonardo]

    get :mark, id: group.id

    expect(User.admin.clipboard).to include(mona_lisa.id, leonardo.id)
  end
  
end
  
