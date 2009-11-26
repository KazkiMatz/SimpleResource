require 'memcached'
require 'digest/md5'

module SimpleResource
  module TtEntityBackend

    def self.included(base)
      base.extend ClassMethods
      base.__send__ :include, InstanceMethods
    end

    module ClassMethods
      def conn
        $tt_conn ||= if PRELOAD_CACHE
                       MemcacheManager.new(TT_HOST[0])
                     else
                       Memcached.new(TT_HOST[0])
                     end
      end

      def get(query)
        key = "#{query[:collection_name]}/#{query[:key]}"
        body = conn.get(memcache_key(query), false)
        raise SimpleResource::Exceptions::NotFound, "entity not found #{key}" unless body && body.length > 0
        body
      rescue Memcached::NotFound
        raise SimpleResource::Exceptions::NotFound, "entity not found #{key}"
      end

      def put(query, body)
        conn.set(memcache_key(query), body, 0, false)
        true
      end

      def delete(query)
        conn.delete(memcache_key(query)) rescue nil
      end

      # private

      def writelock_key(query)
        location = "/#{query[:collection_name]}/#{query[:key]}"

        "#{TT_PREFIX}WRITELOCK_#{Digest::MD5.hexdigest(location)}"
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
        "#{TT_PREFIX}#{query[:collection_name]}/#{query[:key]}"
      end

    end

    module InstanceMethods

    end
  end
end
