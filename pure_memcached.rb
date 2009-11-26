require 'memcache'
require 'memcached'

module SimpleResource
  class PureMemcached

    def initialize *args
      @conn = MemCache.new(*args)
    end

    def get key, marshal = true
      @conn.get key, !marshal
    end

    def add key, value, expiry = 0, marshal = true
      res = @conn.add key, value, expiry, !marshal
      if res[0,10] == 'NOT_STORED'
        raise Memcached::NotStored
      end
    end

    def delete key
      @conn.delete key
    end

    def set key, value, expiry = 0, marshal = true
      @conn.set key, value, expiry, !marshal
    end
  end
end
