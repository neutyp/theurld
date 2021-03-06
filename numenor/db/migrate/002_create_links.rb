class CreateLinks < ActiveRecord::Migration
  def self.up
    create_table :links do |t|
      t.column :domain_id, :integer, :null => false
      t.column :category_id, :integer
      
      t.column :title, :text, :null => false
      t.column :uri, :text, :null => false
      t.column :path, :text
      t.column :variables, :text
      
      t.column :code, :string, :null => false
      
      t.column :created_on, :datetime, :null => false
      t.column :latest_on, :datetime, :null => false
      t.column :updated_on, :datetime, :null => false
    end
  end

  def self.down
    drop_table :links
  end
end
