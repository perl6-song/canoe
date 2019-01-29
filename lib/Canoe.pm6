
unit class Canoe is export;

# we need lock using the IO::Handle.lock/unlock and require
# PLEASE NOTICE: require lock only work in current module
state $threadlock = Lock::Async.new;
state $requirelock= Lock::Async.new;

has $.file;
has $!lock;

submethod TWEAK() {
    $!file = $!file.IO;
    $!lock = $!file.dirname.IO.add(".lock").open(:create, :rw);
}

class PlugInfo { ... }

method e() {
    $!file.e;
}

method create(--> Promise) {
    start {
        self!lock();
        LEAVE { self!unlock() }
        spurt($!file, Rakudo::Internals::JSON.to-json(
            %{ plugins => [] }
        ));
    }
}

# need .lock
# JSON CONFIG:
# {"plugins": [ { "name": "Plugin1", "enable": true }, ... ] }
method load(--> Promise) {
    start {
        my @plugins;
        for @(self!read-config()<plugins>) {
            @plugins.push(self!make-plugin-info(.<name>.Str, .<enable>.Bool))
        }
        @plugins;
    }
}

method Supply(--> Supply) {
    supply {
        for @(self!read-config()<plugins>) -> $p {
            emit self!make-plugin-info($p<name>.Str, $p<enable>.Bool);
        }
    }
}

# need .lock
method register(Str $name, Bool $enable --> Promise) {
    start {
        my %config = self!read-config();
        for @(%config<plugins>) {
            die "Plugin already exists: $name", if .<name>.Str eq $name;
        }
        %config<plugins>.push(%{ name => $name, enable => $enable });
        self!write-config(%config);
    }
}

method unregister(Str $name --> Promise) {
    start {
        my %config = self!read-config();
        for ^+@(%config<plugins>) -> $index {
            if %config<plugins>[$index]<name> eq $name {
                %config<plugins>.splice($index, 1);
                last;
            }
        }
        self!write-config(%config);
    }
}

method !lock() {
    $threadlock.protect: {
        $!lock.lock();
    }
}

method !unlock() {
    $threadlock.protect: {
        $!lock.unlock();
    }
}

method !read-config() {
    self!lock();
    LEAVE { self!unlock(); }
    Rakudo::Internals::JSON.from-json(slurp($!file));
}

method !write-config(%config) {
    self!lock();
    LEAVE { self!unlock(); }
    spurt($!file, Rakudo::Internals::JSON.to-json(%config));
}

method !make-plugin-info(Str $name, Bool $enable) {
    $requirelock.protect: {
        PlugInfo.new(
            enable      => $enable,
            plugin      => do {
                ((try require ::($name)) === Nil) ?? Any !! ::($name)
            },
            name        => $name,
            installed   => !((try require ::($name)) === Nil),
        )
    }
}

class PlugInfo {
    has $.enable;
    has $.plugin;
    has $.installed;
    has $.name;

    method get-instance(*%_) {
        $!plugin.new(|%_);
    }
}
