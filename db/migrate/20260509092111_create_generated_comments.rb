class CreateGeneratedComments < ActiveRecord::Migration[8.1]
  def change
    create_table :generated_comments do |t|
      t.string :file_id
      t.integer :year
      t.text :comments_json

      t.timestamps
    end
  end
end
