# Brush

> Stop bash-ing out scripts.. code is art. You need the right tools.

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

Available where? Let's hide it away in a `.brush/deps` directory. This can
be configured using the `BRUSH_DEPS_DIR` environment variable, and ignored
using `.gitignore`.

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
in the global namespace. We need to be able to de-reference the function from
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
    "current_year.get"
)
```

And now we can import the library, and call the public functions.

```bash {cmd}
#!/usr/bin/env bash

source <(brush v0.0.3)

import "expelledboy/log@v0.0.2"
import "expelledboy/current-year@v0.0.2"

log.info "Hello from the year $(current_year.get)!" # Hello from the year 2023!
```

### Modules

One thing I don't like about the current design is the repetition of the
library name. It's not a big deal, but it would be nice if we could just
specify the name of the library once.

```bash {cmd}
source <(brush v0.0.3)

module "current_year"

timestamp() { date; }
define timestamp

get() { timestamp | cut -d' ' -f6; }
define get

public=(get)
```

I am not going to go into the implementation details of this, but it's
basically just introducing a new `module` function, which defines a new
namespace for the library. When the `define` function is called, it will
automatically prefix the function with the module name. And when the `import`
function is called, it will will do the same.

At this point most of the "magic" is done. We have a way to import libraries,
and we have a way to define libraries. But there are still a few things that
could be improved.

### Function Arguments

This is a big one. Bash does not have a way to declare function arguments.
A function can begin running even if the arguments are not supplied. And
even if they are, we don't know if they are valid.

Well that's not entirely true. Bash has two arg parsing functions, `getopts`
and `getopt`. I have been writing bash scripts for years, and the effort
required is not worth the reward. We can do better.

Seeing as we already have to define functions, why not just define the
arguments there as well?

And if we thing about it, the documentation for the function arguments is
a give us a pretty good idea of what the function does. So let be combine
the documentation and the function definition.

```bash {cmd}
user_profile() {
    echo <<EOF
{
    "name": "$NAME",
    "email": "$EMAIL",
    "age": "$(
        if [[ -n "${AGE:-}" ]]; then
            echo "$AGE"
        else
            echo null
        fi
    )"
}
EOF
}

define user_profile <<EOF
DESCRIPTION:
    Create a user profile in json format.

ARGUMENTS:
    # Users full name
    -n, --name <string>
    # Primary email address
    -e, --email <regex(^[a-z0-9._%+-]+@[a-z0-9.-]+\.[a-z]{2,4}$)>
    # The age of the user in years
    --age? <number(0-120)>
    # Department
    --department? <enum("engineering", "marketing", "sales")> = "engineering"
EOF
```

The API is simple:
```
define <function> <<EOF
DESCRIPTION:
    <description>

ARGUMENTS:
    [# <description>]
    [<short>,] <long> <parser[(<options>)]> [= <default>]
```

The `define` function will wrap the function in a new function that will
parse the arguments, against the supplied parsers, and then call the original
function with the parsed arguments made available as local readonly variables.

Python developers will be familiar with this pattern. Decorators.

We get `--help` for free. And the error messages are pretty good.

```
$ example.user_profile --help
DESCRIPTION:
    Create a user profile in json format.

ARGUMENTS:
    -n, --name          Users full name
    -e, --email         Primary email address
        --age?          The age of the user in years
        --department?   Department (default: engineering)
    -h, --help          Show this help message and exit.

$ example.user_profile
ERROR: Missing required arguments:
    -n, --name <string>
    -e, --email <regex(^[a-z0-9._%+-]+@[a-z0-9.-]+\.[a-z]{2,4}$)>

$ example.user_profile -n "John Doe" -e "bad email" --age 200
ERROR: Invalid argument:
    --email "bad email"; does not match pattern ^[a-z0-9._%+-]+@[a-z0-9.-]+\.[a-z]{2,4}$
    --age "200"; is not in range 0-120
```

An added benefit of this approach is that we can standardize the format of
documentation, and pretty it up. This makes building tooling around it much
easier.

With that in mind let's expose a `--definition` flag, that will print the
function definition.

```bash {cmd}
$ example.user_profile --definition
{
    "name": "user_profile",
    "module": "example",
    "description": "Create a user profile in json format.",
    "arguments": [
        {
            "name": "name",
            "alias": "n",
            "description": "Users full name",
            "parser": "string",
            "required": true
        },
        {
            "name": "email",
            "alias": "e",
            "description": "Primary email address",
            "parser": {
                "name": "regex",
                "pattern": "^[a-z0-9._%+-]+@[a-z0-9.-]+\\.[a-z]{2,4}$"
            },
            "required": true
        },
        {
            "name": "age",
            "description": "The age of the user in years",
            "parser": {
                "name": "number",
                "min": 0,
                "max": 120
            },
            "required": false
        },
        {
            "name": "department",
            "description": "Department",
            "parser": {
                "name": "enum",
                "options": [
                    "engineering",
                    "marketing",
                    "sales"
                ]
            },
            "default": "engineering",
            "required": false
        }
    ]
}
```

Now things are starting to get interesting!

### Type Checking

If you think I am joking, I am not. I am going to add type checking to bash.

What makes sense to me is to use the same parsers that we use for arguments.
Theoretically while we are hashing the function, we could parse the arguments
that are being passed to the function, and then validate them against the
definition.

We don't need to do this at runtime. It would be better to write a brush
command that will `--validate` the script. This way we can catch errors before
the script is even run.

```
$ brush --validate main.sh
ERROR: Function call does not match definition:
    main.sh:6: example.user_profile --name "John Doe"
    Missing required arguments:
        -e, --email <regex(^[a-z0-9._%+-]+@[a-z0-9.-]+\.[a-z]{2,4}$)>
```

But Anthony, if we have type checking, can we do code completion? Yes we can!

### Code Completion

Where is code completion most useful? In a language server. And where is a
language server most useful? In an IDE.

I am not going to write an IDE for bash. I am not even going to write a
language server really. What important is that we have a protocol that we can
use to communicate with a language server.

This is where `brush serve` command comes in. It will start an http server,
that will listen for requests, and respond with the appropriate data.

```
$ brush serve
Listening on http://localhost:1337
```

And then in another terminal, we can use `curl` to make requests.

```json
$ curl -s "http://localhost:1337/definition?function=example.user_profile" | jq
{
  "name": "user_profile",
  "module": "example",
  "description": "Create a user profile in json format.",
  "arguments": [
    // ...
  ]
}

$ curl -s "http://localhost:1337/definitions" | jq
[
  {
    "name": "user_profile",
    "module": "example",
    "description": "Create a user profile in json format.",
    "arguments": [
      // ...
    ]
  },
  {
    "name": "log.info",
    "module": "expelledboy/log",
    "description": "Log a message with the INFO level.",
    "arguments": [
      // ...
    ]
  }
]
```

### VSCode Extension

Now that we have a language server, we can write a VSCode extension that will
use it to provide code completion, documentation, error checking, syntax
highlighting, etc.

<!--
![VSCode Extension](./docs/vscode-extension.png)

The VSCode extension is available [here](https://marketplace.visualstudio.com/items?itemName=expelledboy.brush).
-->

Work still in progress.. contributions welcome!

### Testing

If you have ever written a bash script, you know how painful it is to test.
There is a popular library called [bats](https://github.com/sstephenson/bats) that
tries to solve this problem. I have used it, it's great.

I do not think I can do better than bats, but integrating it into brush isn't
easy. There is abit too much magic going on. Ultimately we do not need all the
features of bats. We just need a way to run a function, and assert the output.

I was a fan of [tap](https://testanything.org/), and I have used it in afew
projects. It's simple, easy to understand, and easy to implement.

As a developer, you just need to write a test script, that when run, will
output a tap stream. The tap stream is then parsed by a tap consumer, which
will output the results.

Let's write a test script for the `user_profile` function.

```bash {cmd}
#!/usr/bin/env bash

source <(brush v0.0.3)
module "person"
import --dev "expelledboy/tap@v0.0.1"

tap.plan 2

tap.before_all <<EOF
    # Mock date
    date() { echo "2021"; }
EOF

calculate_age() {
    year="$(echo $DATE_OF_BIRTH | cut -d'-' -f1)"
    echo $(( $(date +%Y) - $year ))
}

define calculate_age <<EOF
DESCRIPTION:
    Calculate the age of a person.

ARGUMENTS:
    -d, --date-of-birth <regex(^[0-9]{4}-[0-9]{2}-[0-9]{2}$)>
EOF

tap.test "calculate age" <<EOF
    calculate_age --date-of-birth "2000-01-01" \
        | assert --output 21 --exit-code 0
EOF

tap.test "calculate age (invalid date)" <<EOF
    calculate_age --date-of-birth "2000-01-01-01" \
        | assert --exit-code 1
EOF
```

And then we can run the test script.

```
$ brush test
TAP version 14
1..2
ok 1 - calculate age
ok 2 - calculate age (invalid date)
```

### Packaging

At this point we have a pretty good developer experience. But we are still
missing one thing. How could we distribute our scripts?

We could just use git, but that's not ideal. It includes files that are not
needed during runtime. Also our scripts may depend on other libraries, which
would need to be installed, therefore you would need internet access to run
the script.

What we need is a way to package our scripts, and all their dependencies, into
a single distributable archive. And I never have understood why packaging tools
do not by default to distribute to all platforms... With brush, we have the
opportunity to do this.

In the root of the project, we can add a `package.sh` script.

```bash {cmd}
#!/usr/bin/env bash

source <(brush v0.0.3)

import --dev "expelledboy/package@v0.0.1"

author "Anthony Jackson <expelledboy>"
compile "bin/tap.sh"
license "Apache-2.0"

debian <<EOF
    Depends: bash (>= 4.4)
EOF

github
```

And then we can run the brush commands to package and publish the script.

```
$ brush package
Packaging tap@v0.0.1
- bin/tap.sh
- bin/tap.sh.sha256
- LICENSE
- README.md
You can now test the distribution using:
    brush install --dev github
```

```
$ brush publish
Publishing tap@v0.0.1
- https://ftp.us.debian.org/debian/pool/main/b/brush/tap_0.0.1_all.deb
- https://github.com/brush/tap/releases/download/v0.0.1/person.sh
You can now install the package using:
    brush install expelledboy/tap@v0.0.1
```

And then we can install the package.

```
$ brush install expelledboy/tap@v0.0.1
Downloading expelledboy/tap@v0.0.1
Installing expelledboy/tap@v0.0.1
```

And then we can run globally.

```
$ tap --help # or `man tap`
USAGE:
    tap [OPTIONS] COMMAND [ARGS]...

DESCRIPTION:
    Tap is a test harness for bash.

COMMANDS:
    run     Run tests.
    plan    Define the test plan.
    test    Define a test case.

    Run `tap COMMAND --help` for more information on a command.

OPTIONS:
    -h, --help  Show this help message and exit.
```

This is pretty cool. It's looking like we have a pretty good developer
experience.

### Improvements

One issue I have with the current design is we write the implementation before
the definition.  My pattern recognition skills expects documentation and types
to be just above the implementation.

This can be achieved. But we need to make a few changes.

Firstly, we need to change the `define` function to only save the function
definition. Then add the end of the script, after all the functions have been
defined and implemented, we need to "compile" the functions.

This is typically where the `main` function would be defined. So let's just
use that.

```bash {cmd}
#!/usr/bin/env bash

source <(brush v0.0.3)

import "expelledboy/log@v0.0.2"
import "expelledboy/tap@v0.0.1"

tap.plan 2

defined hello_world <<EOF
DESCRIPTION:
    Print hello world.

ARGUMENTS:
    -n, --name? <string>
EOF

hello_world() (
    if [[ -n "${NAME:-}" ]]; then
        log.info "Hello $NAME!"
    else
        log.info "Hello world!"
    fi
)

tap.test "hello world" <<EOF
    hello_world | assert --output "Hello world!"
EOF

tap.test "hello world (with name)" <<EOF
    hello_world --name "John Doe" | assert --output "Hello John Doe!"
EOF

case main hello_world in
    ok:called)
        exit
        ;;
    ok:sourced)
        public=(
            "hello_world"
        )
    error:not-implemented)
        log.die -e not-implemented \
            "Oops, you reached some code the developer has not implemented yet."
        ;;
    *)
        log.die "Oops, something went wrong."
        ;;
esac
```

We can now run this as a standalone script, or import it as a library.

Let's try to unpack what is going on here in the case statement. Firstly, we
are calling the `main` function with the `hello_world` function. The `main`
function will then check if the `hello_world` function is defined. If it is,
it will call it, and return the exit code. If it is not, it will return
`error:not-implemented`.

What magic is this? Well, bash actually has standard exit codes. So all
we need is a way to map the exit codes to a string. And we can do that with
a simple array.

```bash {cmd}
# See: https://www.cyberciti.biz/faq/linux-bash-exit-status-set-exit-statusin-bash/
declare -A __brush_exit_codes=(
    [0]="ok"
    [1]="error:not-permitted"
    [2]="error:no-such-file"
    [3]="error:no-such-process"
    [4]="error:interrupted-system-call"
    [5]="error:input-output-error"
    # ...
)
```

More on this later.

If the `main` function returns `ok:called`, we can can just exit. If it returns
`error:*`, we can call `log.die` with the exit code, and an error message.

But what if the `main` function returns `ok:sourced`? Well, that means that
we are imported, and we need to export the public functions.

### Standard Library

Unless there is a `stdlib` we are going to see hundreds of implementations of
`logger`, `http`, `json`, `date`, etc. At the same time, we I don't think we
we should force users of brush to use our implementations.

So we have to be very opinionated about what goes into the `stdlib`. It should
be small, extremely well tested, well documented, and only include the most
commonly used functions. Yes, this means bash finally has a `string` library!

```bash {cmd}
#!/usr/bin/env bash

source <(brush v0.0.5)

import "brush/stdlib@v0.0.1"

define hello_world <<EOF
    -n, --name? <string>
EOF

hello_world() (
    local name

    log.debug "Running on $(os.name)"

    if ! env.exists "NAME"; then
        log.die "Hello world!"
    fi

    name="$(echo $NAME | string.trim | string.capitalize)"

    if [[ "$(string.length "$name")" -lt 3 ]]; then
        log.die -e invalid-argument \
            "Name must be at least 3 characters long."
    fi

    log.info "Hello $name! Your name is $(string.length "$name") characters long."
)

case main hello_world in
    ok:called) exit ;;
    *) log.die ;;
esac
```

Considering how often we will use functions in the `stdlib`, it makes sense to
to be able to import it without having to specify the full name.

```bash {cmd}
import "brush/stdlib@v0.0.1"

includes=(
    "string: trim, capitalize, length as s_len",
    "log: info as log"
)

name_length() {
    local name length

    name="$(echo $1 | trim | capitalize)"
    length="$(s_len $name)"

    log "Hello, $name! Your name is $length characters long."
}

case main name_length in
    ok:called) exit ;;
    *) log.die ;;
esac
```

I am not going to dump the reference manual here, its all available in the
[docs](./docs/stdlib.md).

### Local Variables

You may have noticed that we always use `local` when defining variables. This
is good practice, so that we don't pollute the global namespace. But it's also
a bit annoying. How about we just make all variables local by default?

And some users of `shellcheck` might have come across the following warning:

```
SC2155: Declare and assign separately to avoid masking return values.
```

This is still a work in progress.. if you have any ideas, please let me know.

## Closing Words

This is still very much a work in progress. But I have to tell you it's been
a lot of fun working with bash + brush! :)

Happy hacking!