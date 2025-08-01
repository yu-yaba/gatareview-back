class CreateUsers < ActiveRecord::Migration[7.0]
  def change
    unless table_exists?(:users)
      create_table :users do |t|
        t.string :email, null: false
        t.string :name, null: false
        t.string :provider, null: false
        t.string :provider_id, null: false
        t.string :avatar_url

        t.timestamps
      end
    end

    unless index_exists?(:users, :email)
      add_index :users, :email, unique: true
    end
    unless index_exists?(:users, [:provider, :provider_id])
      add_index :users, [:provider, :provider_id], unique: true
    end
  end
end
