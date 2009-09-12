module SimpleResource
  class MysqlIndex < ActiveRecord::Base
    establish_connection :index
    set_table_name "indices"

    class << self
      def records index_id, page, page_size
        sql =<<"EOS"
SELECT * FROM indices 
WHERE index_id = #{index_id.to_i} 
ORDER BY sort DESC 
LIMIT #{page_size.to_i} 
OFFSET #{page_size.to_i * (page.to_i - 1)} 
EOS
        self.find_by_sql(sql)
      end

      def record_count index_id
        sql =<<"EOS"
SELECT COUNT(*) FROM indices 
WHERE index_id = #{index_id.to_i}
EOS
self.count_by_sql(sql)
      end

      def insert_record index_id, entity_id, sort
        sql =<<"EOS"
INSERT INTO `indices` (`index_id`, `entity_id`, `sort`) VALUES (?, ?, ?)
EOS
        self.connection.execute(self.sanitize_sql([sql, index_id.to_i, entity_id, sort.to_i]))
      end

      def remove_record index_id, entity_id
        self.delete_all(["index_id = ? AND entity_id = ?", index_id, entity_id])
      end

    end
  end
end
