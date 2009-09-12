module SimpleResource
  module MysqlIndexBackend

    def self.included(base)
      base.extend ClassMethods
      base.__send__ :include, InstanceMethods
    end

    module ClassMethods

      def get_index(query, params = {})
        params[:page_size] ||= 10
        params[:page] ||= 1
        params[:page] = 1 unless params[:page].to_i >= 1

        [
          SimpleResource::MysqlIndex.records(index_id(query[:index_name]), params[:page], params[:page_size]).map{|record| [record.entity_id, record.sort]},
          Pager.new('totalnum' => SimpleResource::MysqlIndex.record_count(index_id(query[:index_name])),
                    'size' => params[:page_size],
                    'from' => params[:page_size] * (params[:page] - 1))
        ]
      end

      def add_to_index(query)
        SimpleResource::MysqlIndex.insert_record index_id(query[:index_name]), query[:id].to_s, query[:params][:sort]
      end

      def remove_from_index(query)
        SimpleResource::MysqlIndex.remove_record index_id(query[:index_name]), query[:id].to_s
      end

      def index_id(name)
        begin
          return SimpleResource::IndexName.find(name).alias_of
        rescue SimpleResource::Exceptions::NotFound
          index_name = SimpleResource::IndexName.create("index_name" => name)
          SimpleResource::IndexName.create("id" => name, "alias_of" => index_name.id)
          return index_name.id
        end
      end

      def delete_index(name)
        SimpleResource::IndexName.find(name).destroy
      rescue
        nil
      end
    end

    module InstanceMethods

    end
  end
end
