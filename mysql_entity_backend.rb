require 'memcached'
require 'digest/md5'
require 'mysql'
require 'yaml'

PATH_TO_DB_CONFIG = RAILS_ROOT + '/config/database.yml'

module SimpleResource
  module MysqlEntityBackend

    def self.included(base)
      base.extend ClassMethods
      base.__send__ :include, InstanceMethods
    end

    module ClassMethods

      def conn
        $memcache_conn ||= Memcached.new(MEMCACHE_HOST[0])
      end

      def get(query)
        key = "#{query[:collection_name]}/#{query[:key]}"
        begin
          body = conn.get(memcache_key(query), false)
        rescue Memcached::NotFound
          body = mysql_select key
          conn.set(memcache_key(query), body, 0, false)
        end

        raise SimpleResource::Exceptions::NotFound, "entity not found #{key}" unless body && body.length > 0
        body
      end

      def put(query, body)
        begin
          return false if body == get(query)
        rescue SimpleResource::Exceptions::NotFound
        end

        mysql_insert_or_update "#{query[:collection_name]}/#{query[:key]}", body
        conn.set(memcache_key(query), body, 0, false)

        true
      end

      def delete(query)
        mysql_delete "#{query[:collection_name]}/#{query[:key]}"
        conn.delete(memcache_key(query)) rescue nil
      end

      # private

      def writelock_key(query)
        location = "/#{query[:collection_name]}/#{query[:key]}"

        "#{MEMCACHE_PREFIX}WRITELOCK_#{Digest::MD5.hexdigest(location)}"
      end

      def get_mutex(query, queued = true)
        conn.add writelock_key(query), Time.now.to_i.to_s, 0, false
        true
      rescue Memcached::NotStored
        # 30sec to emergency release
        if lock = (conn.get(writelock_key(query), false) rescue nil)
          if Time.now.to_i > lock.to_i + 30
            release_mutex(query)
          end
        end
        false
      end

      def release_mutex(query)
        conn.delete writelock_key(query) rescue nil
      end

      def memcache_key(query)
        "#{MEMCACHE_PREFIX}#{query[:collection_name]}/#{query[:key]}"
      end

      private

      def db_config
        $mysql_entity_config ||= YAML.load_file(PATH_TO_DB_CONFIG)['entity']
      end

      def db_conn key
        selected = Digest::MD5.digest(key)[0] % db_config['shards'].size
        $mysql_entity_conn ||= []
        return $mysql_entity_conn[selected] if $mysql_entity_conn[selected]

        $mysql_entity_conn[selected] = Mysql.connect(db_config['shards'][selected]['host'],
                                                     db_config['shards'][selected]['username'],
                                                     db_config['shards'][selected]['password'],
                                                     db_config['shards'][selected]['database'],
                                                     db_config['shards'][selected]['port'])
        $mysql_entity_conn[selected].reconnect = true
        $mysql_entity_conn[selected]
      end

      def mysql_select key
        key = key_notation(key)
        row = db_conn(key).query("SELECT body FROM entities WHERE entity_group_entity_id = #{key}").fetch_row
        row ? row.first : nil
      end

      def mysql_insert_or_update key, body
        time = "'#{Time.now.strftime("%Y-%m-%d %H:%M:%S")}'"
        key = key_notation(key)
        body = bin_notation(body)
        db_conn(key).query "INSERT INTO entities (entity_group_entity_id, body, created_at, updated_at) VALUES (#{key}, #{body}, #{time}, #{time}) ON DUPLICATE KEY UPDATE body = #{body}, updated_at = #{time}"
      end

      def mysql_delete key
        key = key_notation(key)
        db_conn(key).query "DELETE FROM entities WHERE entity_group_entity_id = #{key}"
      end

      def key_notation key
        if key[/[^A-Za-z0-9\-_:.\/=&%+]/]
          raise SimpleResource::Exceptions::InvalidKey, key
        end
        "'#{key}'"
      end

      def bin_notation value
        "x'#{value.unpack("H*")[0]}'"
      end
    end

    module InstanceMethods

    end
  end
end
