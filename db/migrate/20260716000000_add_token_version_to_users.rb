# frozen_string_literal: true

class AddTokenVersionToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :token_version, :integer, null: false, default: 0
  end
end
