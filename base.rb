require 'json/ext'

module SimpleResource
  class ElasticHash < Hash
    def initialize(hash)
      hash.each {|key, value| self[key] = value }
    end

    def id
      self["id"]
    end

    def id= value
      self["id"] = value
    end

    def method_missing(key, *args)
      key_str = key.to_s
      suffix = key_str.last[-1]
      if suffix == "="[0]
        self[key_str[0..-2]] = args.first
      else
        key_str = key_str[0..-2] if suffix == "?"[0]
        #raise NameError unless has_key?(key_str)
        return nil unless has_key?(key_str)
        if self[key_str].class == Hash
          self[key_str] = ElasticHash.new(self[key_str])
        elsif self[key_str].class == Array
          self[key_str] = ElasticArray.new(self[key_str])
        else
          self[key_str]
        end
      end
    end
  end

  class ElasticArray < Array
    def [] *index
      if index.size > 1
        self[index] = super.map{|item| elastically item}
      elsif index[0].class == Range
        self[index[0]] = super.map{|item| elastically item}
      else
        if super
          self[index[0]] = elastically super
        else
          super
        end
      end
    end

    def first
      self[0]
    end

    def last
      self[-1]
    end

    def each
      (0...size).each do |i|
        yield self[i]
      end
    end

    def map
      result = []
      self.each {|item| result << yield(item)}
      result
    end

    private

    def elastically obj
      if obj.class == Hash
        ElasticHash.new(obj)
      elsif obj.class == Array
        ElasticArray.new(obj)
      else
        obj
      end
    end
  end

  class Base
    class << self
      def json_encode hash
        hash.to_json
      end

      def json_decode str
        JSON.parse str
      end

      def collection_name
        self.to_s
      end

      def paginate(index_name, params = {})
        returning get_index({:index_name => index_name}, params) do |list|
          list[0].map!{ |item| self.find(item[0]) }
        end
      end

      def find(key)
        self.new(self.json_decode( get(:collection_name => collection_name, :key => key) ))
      end

      def find_with_lock(key)
        get_lock(key)
        obj = self.find(key)
        yield obj
        obj
      ensure
        release_lock(key)
      end

      def find_or_create(key, attributes)
        self.find(key)
      rescue SimpleResource::Exceptions::NotFound
        self.create(attributes.update("id" => key))
      end

      def find_or_create_with_lock(key, attributes)
        get_lock(key)
        obj = self.find_or_create(key, attributes)
        yield obj
        obj
      ensure
        release_lock(key)
      end

      def create attributes
        attributes["id"] = gen_key! unless attributes["id"]
        returning self.new(attributes) do |obj|
          put({:collection_name => collection_name, :key => obj.id}, json_encode(obj.attributes))
        end
      end

      def get_lock key
        until get_mutex(:collection_name => collection_name, :key => key)
          sleep 0.1
        end
      end

      def release_lock key
        release_mutex(:collection_name => collection_name, :key => key)
      end

      def gen_key!
        key_increment = find_or_create_with_lock('key_increment', {'counter' => 0}) do |k|
                          k.counter += 1
                          k.save
                        end
        begin
          self.find(key_increment.counter)
          raise SimpleResource::Exceptions::DuplicatedKey
        rescue SimpleResource::Exceptions::NotFound
        end

        key_increment.counter
      end
    end

    def initialize attributes = {}
      @attributes = ElasticHash.new(attributes)
    end

    def == another
      return false unless another.is_a?(self.class)
      self.id == another.id
    end

    def copy
      self.class.new(Marshal.load(Marshal.dump(@attributes)))
    end

    def id
      @attributes["id"]
    end

    def id= value
      @attributes["id"] = value
    end

    def save
      self.id = self.class.gen_key! unless self.id
      self.class.put({:collection_name => self.class.collection_name, :key => self.id}, self.class.json_encode(attributes))
      true
    end

    def destroy
      return false unless self.id
      if self.index_names
        self.index_names.dup.each do |index_name|
          remove_from_index index_name
        end
      end
      self.class.delete(:collection_name => self.class.collection_name, :key => self.id)
      true
    end

    def lock
      self.class.get_lock(id)
      yield self
    ensure
      self.class.release_lock(id)
    end

    def method_missing(name, *args)
      @attributes.__send__ name, *args
    end

    def attributes
      @attributes || {}
    end

    def remove_from_index index_name
      return unless self.id
      self.class.remove_from_index(:index_name => index_name, :id => self.id)

      if self.index_names
        self.index_names.delete index_name
        self.save
      end
    end

    def add_to_index index_name, sort_val
      return unless self.id
      self.class.add_to_index({:index_name => index_name, :id => self.id, :params => {:sort => sort_val}})

      if self.index_names
        if !self.index_names.include?(index_name)
          self.index_names << index_name
          self.save
        end
      else
        self.index_names = [index_name]
        self.save
      end
    end

  end

  module Exceptions
    class NotFound < StandardError; end
    class DuplicatedKey < StandardError; end
  end
end
