class AddContentHashToGeneratedComments < ActiveRecord::Migration[8.1]
  def change
    add_column :generated_comments, :content_hash, :string
  end
end
