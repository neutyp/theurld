class CreateLinkQueues < ActiveRecord::Migration
  def self.up
    create_table :link_queues do |t|
      t.column :member_id, :integer, :null => false
      
      t.column :urls, :text
      
      t.column :created_on, :datetime, :null => false
      t.column :updated_on, :datetime, :null => false
    end
  end

  def self.down
    drop_table :link_queues
  end
end
