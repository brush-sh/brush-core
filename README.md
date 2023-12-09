# Brush

> Stop bash-ing out scripts..

Do you cringe when you see a bash script in your source tree? Who knows what
monstrosity of a script you'll find. I believe this is because developer
experience was never a priority for bash. It's a language that was designed to
be used by system administrators, not developers.

Brush attempts to align the developer experience with that of modern languages,
while still being bash.

## Challenges

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

source <(brush v1.0.0)
```

To install the `brush` command, we can just download it from github, and add it
somewhere on the `$PATH`.

```bash {cmd}
$ curl -sL https://raw.githubusercontent.com/expelledboy/brush/master/brush.sh > /usr/local/bin/brush
$ chmod +x /usr/local/bin/brush
```