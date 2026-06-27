# typed: true

module Async
  class Barrier
    def initialize(parent: T.unsafe(nil)); end
    def async(*arguments, parent: T.unsafe(nil), **options, &block); end
    def wait; end
    def stop; end
  end

  class Queue
    def initialize(parent: T.unsafe(nil)); end
    def <<(item); end
    def dequeue; end
  end

  class Semaphore
    def initialize(limit = T.unsafe(nil), parent: T.unsafe(nil)); end
    def async(*arguments, parent: T.unsafe(nil), **options, &block); end
  end

  class Task
    def with_timeout(duration, exception = T.unsafe(nil), message = T.unsafe(nil), &block); end
  end
end

module Kernel
  def Sync(annotation: T.unsafe(nil), &block); end
end
