module SimpleResource
  class MysqlEntity < ActiveRecord::Base
    establish_connection :entity
    set_table_name "entities"
    set_primary_key "entity_group_entity_id"
  end
end
