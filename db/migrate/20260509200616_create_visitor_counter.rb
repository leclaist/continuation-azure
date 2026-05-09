class CreateVisitorCounter < ActiveRecord::Migration[8.1]
  def change
    create_table :visitor_counters do |t|
      t.integer :count

      t.timestamps
    end
  end
end
