# Brush

> Stop bash-ing out scripts..

Do you cringe when you see a bash script in your source tree? Who knows what
monstrosity of a script you'll find. I believe this is because developer
experience was never a priority for bash. It's a language that was designed to
be used by system administrators, not developers.

Brush attempts to align the developer experience with that of modern languages,
while still being bash.

## Challenges

### Dependency Management

Bash scripts are often written with a lot of boilerplate code. Why?

One reason is bash does not have dependency management. This means that
developers can not re-use code.

Before we tackle this problem, let's first we need a pattern for writing bash
re-usable code. An established pattern is as follows:

```bash {cmd}
#!/usr/bin/env bash

timestamp() (
    date -u +"%Y-%m-%dT%H:%M:%SZ"
)

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    timestamp
fi
```

This allows the script to be used as a library, and as a standalone script.

```bash {cmd}
$ ./timestamp.sh
2020-01-01T00:00:00Z
```

```bash {cmd}
$ source ./timestamp.sh
$ timestamp
2020-01-01T00:00:00Z
```

Next issue is how do we publish this code? Ideally it should be available on
some sort of versioned repository. Using github is the obvious choice here.

```bash {cmd}
$ git add timestamp.sh
$ git commit -m "Add timestamp function"
$ git tag -a v1.0.0
$ git remote add origin git@github.com:expelledboy/timestamp.git
$ git push --follow-tags
```

And then in another project:

```bash {cmd}
$ git clone git@github.com:expelledboy/timestamp.git timestamp
$ (cd timestamp && git checkout v1.0.0)
```

```bash {cmd}
$ source timestamp/timestamp.sh
$ timestamp
2020-01-01T00:00:00Z
```

If we can agree on this pattern, we can start building tooling around it.

I like how [deno](https://deno.land/) and [go](https://golang.org/) handles
dependencies. They both use URLs inlined in the source code to specify
dependencies. This is a great pattern, because it allows the developer to
quickly see what dependencies are, where they are coming from, and what version
is being used.

Let's write a `import` function that can handle this. It should download the
source code if it's not already available, and source it.

Available where? Let's hide it away in a `.brush/deps` directory.

Ideally the API of the `import` function should look something like this:

```bash {cmd}
source ./import.sh

import "expelledboy/timestamp@v1.0.0"

echo "UTC: $(timestamp)"
```

```bash {cmd}
$ ./main.sh
Downloading expelledboy/timestamp@v1.0.0
UTC: 2020-01-01T00:00:00Z
$ ./main.sh
UTC: 2020-01-01T00:00:00Z
```

That seems intuitive enough. Let's write the `import` function.

```bash {cmd}
#!/usr/bin/env bash

import() (
    local import="$1"
    local name="${import%%@*}"
    local version="${import##*@}"

    local lib="$name@$version"
    local dir=".brush/deps/$lib"

    if [[ ! -d "$dir" ]]; then
        mkdir -p "$dir"
        curl -sL "https://github.com/${name}/archive/refs/tags/${version}.tar.gz" |
            tar -xz -C "$dir" --strip-components=1
    fi

    for file in "$dir"/*.sh; do
        source "$file"
    done
)
```

Next issue is how to we get the `import` function into our script?

I debated serval ways of solving this problem. But I knew that there was going
to be a need for a `brush` command, so the simplest solution was to just have
the `brush` command bootstrap the itself into the script.

```bash {cmd}
#!/usr/bin/env bash

source <(brush v0.0.2)
```

To install the `brush` command, we can just download it from github, and add it
somewhere on the `$PATH`.

```bash {cmd}
$ curl -sL https://raw.githubusercontent.com/expelledboy/brush/master/bin/brush.sh > /usr/local/bin/brush
$ chmod +x /usr/local/bin/brush
```

And now we can import and use the `timestamp` function.

```bash {cmd}
#!/usr/bin/env bash

source <(brush v0.0.2)

import "expelledboy/timestamp@v1.0.0"

echo "UTC: $(timestamp)" # UTC: 2020-01-01T00:00:00Z
```

This already has a lot of benefits. You do not need to explicitly install
dependencies. Also, brush will install the dependencies of your dependencies!

For example lets write a `log` function that uses the `timestamp` function.

```bash {cmd}
#!/usr/bin/env bash

source <(brush v0.0.2)

import "expelledboy/timestamp@v1.0.0"

log() (
    echo "$(timestamp) $*"
)
```

And then lets use it in our `main.sh` script.

```bash {cmd}
#!/usr/bin/env bash

source <(brush v0.0.2)

import "expelledboy/log@v1.0.0"

log "pretty cool huh?"
```

```
$ ./main.sh
Downloading expelledboy/brush@v0.0.2
Downloading expelledboy/log.sh@v0.0.1
Downloading expelledboy/timestamp.sh@v0.0.1
2023-12-09T20:17:27Z pretty cool, huh?
```

And once the dependencies are cached, it's as fast as any other bash script.

But there is a big flaw in this design. Namespace collisions. What if two
libraries export the same function? But it gets worse...

Imagine the following scenario:

`expelledboy/timestamp@v1.0.0`
- defines `timestamp` format `2020-01-01T00:00:00Z`

`expelledboy/log@v1.0.0`
- imports `expelledboy/timestamp@v1.0.0`
- defines `log`
    - uses `timestamp`

`expelledboy/current-year@v1.0.0`
- defines `timestamp` format `2023-12-09`
- defines `get_current_year`
    - uses `timestamp`

We wish to write a script that logs the current year.

```bash {cmd}
#!/usr/bin/env bash

source <(brush v0.0.2)

import "expelledboy/log@v1.0.0"
import "expelledboy/current-year@v1.0.0"

log "current year: $(get_current_year)"
```

```
# Expected
$ ./main.sh
2023-12-09T20:17:27Z current epoch: 1234567890

# Actual
$ ./main.sh
1234567890 current epoch: 1234567890
```

Also in this case `timestamp` in `expelledboy/current-year@v1.0.0` is really
a private function, and should not be exported.

And this brings us to the next challenge.

### Namespacing

Bash does not have namespaces. This means that all functions are global. This
is a problem because it means that functions can collide.

The solution is quite simple. We just need to prefix all functions with the
name of the library. This is a common pattern in other languages.

```bash {cmd}
import "expelledboy/timestamp@v1.0.0"

log.info() (
    echo "$(timestamp.utc) INFO $*"
)
```

But does this solve the problem? Not quite. It's still possible to have
collisions. Although it's alot less likely. One would need to define a function
with the same name, and the same prefix.

Really what we want is to ensure the functions used during the import process
are exactly the same as the ones used during the execution of the script.

Taking a page from [nix](https://nixos.org/), we could hash the source code of
functions, and use a pointer to the hash when calling the function.

Unless you are already familiar with nix, this might sound a bit confusing. So
let's just jump straight into the implementation.

Conceptually, whenever you define a function, rather than populating the
global namespace, it should be stored in a map. The key of the map should be
the hash of the function, and the value should be the function itself.

The API should be simple.

```bash {cmd}
declare -A __brush_store
declare -A __brush_functions

define() {
    local function="$1"
    local hash code

    code="$(declare -f "$function")"
    hash="$(echo "$code" | shasum -a 256 | cut -d' ' -f1)"

    unset -f "$function"

    __brush_functions["$function"]="$hash"
    __brush_store["$hash"]="$code"
}

timestamp.utc() (
    date -u +"%Y-%m-%dT%H:%M:%SZ"
)

define timestamp.utc
```

But how do we call a function? It's now stored in a map, and no longer defined
in the global namespace.We need to be able to de-reference the function from
the map, and then call it. And preferably is should be as simple as calling a
function.

Let's modify the `define` firstly to rename the function to the hash. And then
replace all calls to functions with a hash with the actual function.

```bash {cmd}
declare -A __brush_functions

define() {
    local function="$1"
    local hash code

    code="$(declare -f "$function")"
    hash="__brush_$(echo "$code" | xxhsum | cut -d' ' -f1)"

    unset -f "$function"

    __brush_functions["$function"]="$hash"

    substitutions=()

    # rename function to hash
    substitutions+=(
        "-e s/^${function}/${hash}/g"
    )

    # substitute dependencies
    for function in "${!__brush_functions[@]}"; do
        substitutions+=(
            "-e s/${function}/${__brush_functions[$function]}/g"
        )
    done

    eval "$(echo "$code" | sed "${substitutions[@]}")"
}
```

Taking the `timestamp.utc` and `log.info` functions from earlier, this is what
they would look like after the substitutions.

```bash {cmd}
__brush_b99d1e382b2a4236 ()
{
    ( date -u +"%Y-%m-%dT%H:%M:%SZ" )
}
__brush_896dcf8eff094d0d ()
{
    ( echo "$(__brush_b99d1e382b2a4236) INFO $*" )
}
```

And that about does it.

But there is one more thing we need to do. If you have been paying attention,
you might have noticed that now we have a new problem. When we import a
library, we are not importing the functions, we are importing the hashes of the
functions.

This means that if we import a library, we would have to know the hashes of the
functions to call them. This is not ideal.

But problem is just another word for opportunity!

### Public and Private Functions

Because function are now obscured by hashes, we can consider all functions
private. This means all we need is a way to make a function public.

Let's add a `public` array, that contains the names of all public functions.
On import, we can iterate over the public functions, and inject them into the
global namespace.

```bash {cmd}
import() (
    # ...

    for file in "$dir"/*.sh; do
        source "$file"

        if [[ -n "${public[*]}" ]]; then
            for function in "${public[@]}"; do
                eval "$function() { ${__brush_functions[$function]} \"\$*\"; }"
            done
        fi

        unset public
    done
)
```

And then in the library, we can define which functions are public.

```bash {cmd}
current_year.timestamp() (
    date
)

define current_year.timestamp

current_year.get() (
    current_year.timestamp | cut -d' ' -f6
)

define current_year.get

public=(
    current_year.get
)
```