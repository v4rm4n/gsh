# Name Clashes

A variable hides any function with the same name, exactly as in a normal Gleam function. At the prompt this is easy to trip over, because your variables and your prompt-defined functions share one namespace:

```gleam
gsh(16)> fn double(x: Int) { x * 2 }
gsh(17)> let double = 3
3 : Int
gsh(18)> double(2)
error: Type mismatch
   ┌─ REPL:36:5
   │
36 │     double(2)
   │     ^^^^^^

This value is being called as a function but its type is:

    Int
```

Give the variable a different name. `:b` lists the variables you've already bound.