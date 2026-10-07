class AddSyllabusDataConstraints < ActiveRecord::Migration[7.0]
  def up
    add_check_constraint :offering_slots, 'day BETWEEN 1 AND 7', name: 'offering_slots_day_range'
    add_check_constraint :offering_slots, 'period BETWEEN 1 AND 7', name: 'offering_slots_period_range'
  end

  def down
    remove_check_constraint :offering_slots, name: 'offering_slots_period_range'
    remove_check_constraint :offering_slots, name: 'offering_slots_day_range'
  end
end
