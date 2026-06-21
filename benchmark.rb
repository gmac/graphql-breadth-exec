require "benchmark"

N_FIELDS = 100
N_OBJS   = 1_000
FIELDS = (1..N_FIELDS).map { |i| :"f#{i}" }
TEMPLATE = FIELDS.map { |k| [k, nil] }.to_h.freeze
INDEX = FIELDS.each_with_index.to_h
Row = Struct.new(*FIELDS)

def bench(label)

  t = Benchmark.realtime { yield }

  puts "%-28s %0.4f sec" % [label, t]

end

# -----------------------------

# 0) Hash#keys

# -----------------------------

bench("Hash#keys") do

  N_OBJS.times do
    h = {}
    FIELDS.each { |k| h[k] = 1 }
  end

end

# -----------------------------

# 1) Hash#replace

# -----------------------------

bench("Hash#replace + assign") do

  N_OBJS.times do

    h = {}

    h.replace(TEMPLATE)

    FIELDS.each { |k| h[k] = 1 }

  end

end



# -----------------------------

# 2) Struct

# -----------------------------

bench("Struct.new + assign") do

  N_OBJS.times do

    r = Row.new

    FIELDS.each { |k| r[k] = 1 }

  end

end



# -----------------------------

# 3) Array + index map

# -----------------------------

bench("Array + index map") do

  N_OBJS.times do

    arr = Array.new(N_FIELDS)

    FIELDS.each { |k| arr[INDEX[k]] = 1 }

  end

end



# -----------------------------

# 4) Struct -> Hash at boundary

# -----------------------------

bench("Struct + to_h") do

  N_OBJS.times do

    r = Row.new

    FIELDS.each { |k| r[k] = 1 }

    r.to_h

  end

end

FIELDS2 = [:id, :name, :email, :posts]
INDEX2  = { id: 0, name: 1, email: 2, posts: 3 }

keys = ["id", "name", "email", "posts"].map(&:freeze)

bench("Build via Hash") do
  N_OBJS.times do
    h = {}
    h[keys[0]] = nil
    h[keys[1]] = nil
    h[keys[2]] = nil

    h[keys[3]] = 3
    h[keys[0]] = 0
    h[keys[2]] = 2
    h[keys[1]] = 1
  end
end

bench("Build via Array / Hash") do
  N_OBJS.times do
    arr = Array.new(keys.length)
    arr[3] = 3
    arr[0] = 0
    arr[1] = 1
    arr[2] = 2
    h = {}
    FIELDS2.each_with_index { |k,i| h[k] = arr[i]}
  end
end
