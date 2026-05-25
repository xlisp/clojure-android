# clojure-android-support

Supplementary Android module that makes Clojure ≥ 1.13 run on Dalvik / ART.

It is **not** part of the main Clojure jar — it imports `android.*` and the
d8/r8 translator, so compiling it into `src/jvm` would break the pure-JVM
Maven build. The main repo only gained the *hooks* it plugs into:

| Where | Change |
|---|---|
| `src/jvm/clojure/lang/DynamicClassLoader.java` | `defineClass` now delegates to the overridable `defineMissingClass`; added `getDataReadersStream()`. Defaults are unchanged for the JVM. |
| `src/jvm/clojure/lang/RT.java` | Added `VM_TYPE` Var; `makeClassLoader()` reflectively builds `DalvikDynamicClassLoader` when `java.vm.name == "Dalvik"`, falling back to the plain loader. |
| `src/clj/clojure/core.clj` | `load-data-readers` asks the context loader for a `data_readers.clj` stream first, then falls back to classpath enumeration. |

Those three changes are transparent and zero-overhead on the JVM; the Dalvik
branch only activates when `java.vm.name == "Dalvik"`.

## Contents

- `src/main/java/clojure/lang/DalvikDynamicClassLoader.java` — **recommended**
  d8 + `InMemoryDexClassLoader` loader (API ≥ 26, no disk writes).
- `src/main/java/clojure/lang/DalvikDynamicClassLoader_dx_legacy.java.alt` —
  legacy dx loader (API ≥ 13). Rename to `DalvikDynamicClassLoader.java` (and
  remove the d8 one) to use it; switch `build.gradle` to `com.android.tools:dx:1.16`.
- `build.gradle` — Android library build, with the main Clojure jar as
  `compileOnly`.

## Build

1. Build the main repo jar (`clojure-1.13.0-master-SNAPSHOT.jar`) and drop it
   under `android-support/libs/`.
2. Add this module to your Gradle settings and build it as an `android-library`.

## App integration

```java
public class MyApp extends Application {
    @Override public void onCreate() {
        super.onCreate();
        DalvikDynamicClassLoader.setContext(this);                 // assets + (dx) cache dir
        Thread.currentThread().setContextClassLoader(              // must precede any Clojure load
            new DalvikDynamicClassLoader(getClassLoader()));
        clojure.lang.RT.var("clojure.core", "require");            // kick off static init
    }
}
```

`AndroidManifest.xml`: `<application android:name=".MyApp" android:largeHeap="true">`.
Put `data_readers.clj` in `app/src/main/assets/` — `getDataReadersStream()`
will load it.

## Verify

- **JVM**: the main repo still builds and tests pass → changes are transparent.
- **Android startup**: `RT.var("clojure.core","+").invoke(1,2)` returns `3`.
- **Android eval**: `Compiler.eval(RT.readString("(+ 1 2)"))` returns `3`
  → the bytecode → DEX path works.

## Note on the data-readers stream path

`core.clj`'s `load-data-reader-file` is typed `^java.net.URL`. On the JVM the
stream branch is never taken (`getDataReadersStream()` returns `null`), so the
build is unaffected. If you rely on `assets/data_readers.clj` on Android and hit
a type error there, adapt `load-data-reader-file` to also accept an
`InputStream`, or wrap the asset in a `jar:`/`file:` URL before handing it back.
