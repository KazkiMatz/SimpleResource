require 'memcached'

module SimpleResource
  module MysqlEntityBackend

    def self.included(base)
      base.extend ClassMethods
      base.__send__ :include, InstanceMethods
    end

    module ClassMethods

      def conn
        if PRELOAD_CACHE
          $memcache_conn ||= MemcacheManager.new(MEMCACHE_HOST[0])
        else
          $memcache_conn ||= Memcached.new(MEMCACHE_HOST[0])
        end
      end

      def get(query)
        begin
          body = conn.get(memcache_key(query))
        rescue Memcached::NotFound
          begin
            record = SimpleResource::MysqlEntity.find("#{query[:collection_name]}/#{query[:key]}")
            body = record.body
          rescue ActiveRecord::RecordNotFound
            body = nil
          ensure
            conn.set(memcache_key(query), body, 0)
          end
        end

        raise SimpleResource::Exceptions::NotFound unless body
        body
      end

      def put(query, body)
        begin
          record = SimpleResource::MysqlEntity.find("#{query[:collection_name]}/#{query[:key]}")
          record.update_attribute(:body, body)
        rescue ActiveRecord::RecordNotFound
          record = SimpleResource::MysqlEntity.new(:body => body)
          record.id = "#{query[:collection_name]}/#{query[:key]}"
          record.save
        end
        conn.delete(memcache_key(query)) rescue nil
      end

      def delete(query)
        begin
          SimpleResource::MysqlEntity.find("#{query[:collection_name]}/#{query[:key]}").destroy
        rescue ActiveRecord::RecordNotFound
        end
        conn.delete(memcache_key(query)) rescue nil
      end

      # private

      def writelock_key(query)
        location = "/#{query[:collection_name]}/#{query[:key]}"

        "#{MEMCACHE_PREFIX}WRITELOCK_#{Digest::MD5.hexdigest(location)}"
      end

      def get_mutex(query, queued = true)
        conn.add writelock_key(query), Time.now.to_i.to_s
        true
      rescue Memcached::NotStored
        # 30sec to emergency release
        if lock = (conn.get(writelock_key(query)) rescue nil)
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
        "#{MEMCACHE_PREFIX}/#{query[:collection_name]}/#{query[:key]}"
      end

    end

    module InstanceMethods

    end
  end
end
