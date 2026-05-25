#!/usr/bin/env bash
#
# Standalone build of clojure-1.13.0-master-SNAPSHOT.jar without Maven/Ant.
# Replicates the build.xml "build" + "jar" targets:
#   1. javac src/jvm           -> target/classes
#   2. write version.properties
#   3. AOT compile core nses   -> target/classes   (clojure.lang.Compile)
#   4. jar target/classes + all src/clj/**/*.clj
#
# Requires: a JDK on PATH, and the two AOT-time deps in ~/.m2:
#   org.clojure/spec.alpha       0.5.238
#   org.clojure/core.specs.alpha 0.4.74
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"

VERSION="$(sed -n 's:.*<version>\(.*\)</version>.*:\1:p' pom.xml | head -1)"
JAR="clojure-${VERSION}.jar"
BUILD="target/classes"
M2="${HOME}/.m2/repository"
SPEC_ALPHA="${M2}/org/clojure/spec.alpha/0.5.238/spec.alpha-0.5.238.jar"
CORE_SPECS="${M2}/org/clojure/core.specs.alpha/0.4.74/core.specs.alpha-0.4.74.jar"

echo ">> version       = ${VERSION}"
echo ">> output jar    = ${JAR}"

for dep in "$SPEC_ALPHA" "$CORE_SPECS"; do
  if [[ ! -f "$dep" ]]; then
    echo "ERROR: missing dependency jar: $dep" >&2
    echo "       (install it into ~/.m2, e.g. via 'mvn dependency:get')" >&2
    exit 1
  fi
done
DEPS="${SPEC_ALPHA}:${CORE_SPECS}"

# Namespaces AOT-compiled into the jar (mirrors build.xml compile-clojure).
NSES=(
  clojure.core clojure.core.protocols clojure.core.server clojure.main
  clojure.set clojure.edn clojure.xml clojure.zip clojure.inspector
  clojure.walk clojure.stacktrace clojure.template clojure.test
  clojure.test.tap clojure.test.junit clojure.pprint clojure.java.io
  clojure.repl clojure.java.browse clojure.java.javadoc clojure.java.shell
  clojure.java.process clojure.java.browse-ui clojure.java.basis.impl
  clojure.java.basis clojure.string clojure.data clojure.reflect
  clojure.datafy clojure.instant clojure.uuid clojure.core.reducers
  clojure.math clojure.tools.deps.interop clojure.repl.deps
)

echo ">> [1/4] clean"
rm -rf target "$JAR" clojure.jar
mkdir -p "$BUILD/clojure"

echo ">> [2/4] javac src/jvm -> $BUILD (Java 8 bytecode)"
find src/jvm -name '*.java' > target/java-sources.txt
javac --release 8 -Xlint:-options -encoding UTF-8 \
      -d "$BUILD" @target/java-sources.txt

echo "version=${VERSION}" > "$BUILD/clojure/version.properties"

echo ">> [3/4] AOT compile clojure namespaces"
java -cp "${BUILD}:src/clj:src/resources:${DEPS}" \
     -Dclojure.compile.path="$BUILD" \
     -Dclojure.compiler.direct-linking=true \
     -Djava.awt.headless=true \
     clojure.lang.Compile "${NSES[@]}"

echo ">> [4/4] package $JAR"
mkdir -p target/jar-stage
cp -R "$BUILD/." target/jar-stage/
# Bundle the .clj sources too (Clojure jars ship both AOT classes and sources),
# preserving package directory structure via tar.
( cd src/clj && find . -name '*.clj' -print | tar -cf - -T - ) \
  | ( cd target/jar-stage && tar -xf - )

mkdir -p target/jar-stage/META-INF
cat > target/jar-stage/META-INF/MANIFEST.MF <<EOF
Manifest-Version: 1.0
Main-Class: clojure.main
Class-Path: .
EOF

( cd target/jar-stage && jar cfm "$ROOT/$JAR" META-INF/MANIFEST.MF . )
cp "$JAR" clojure.jar

echo ""
echo ">> DONE: $ROOT/$JAR"
ls -lh "$JAR"
echo ">> smoke test:"
java -cp "${JAR}:${DEPS}" clojure.main -e '(println "clojure" (clojure-version) "=>" (+ 1 2))'
