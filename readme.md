
# Macromachining — an hfsm macro for Nim

## About
This nimble package contains a fsm macro. It is used for easily implementing
a hierarchical finite state machine with the
[state pattern](https://en.wikipedia.org/wiki/State_pattern)
in Nim.

### The `fsm` macro
Example:

```nim
import macromachining
# todo
```
Notice the typeless parameter `e`, the macro takes care of assigning it the
proper type. Then it is translated roughly into this code:

```nim
# todo
```

### Known quirks
You need to separate the `self` parameter from the rest with a semicolon.

### License

This library is distributed under the MIT license. For more information see `copying.txt`.
