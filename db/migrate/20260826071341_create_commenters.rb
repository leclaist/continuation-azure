class CreateCommenters < ActiveRecord::Migration[8.1]
  def change
    create_table :commenters do |t|
      t.string :username
      t.text :personality
      t.text :memory_summary

      t.timestamps
    end
    add_index :commenters, :username, unique: true
  end
end
