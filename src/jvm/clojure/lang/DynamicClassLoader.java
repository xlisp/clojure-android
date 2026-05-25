/**
 *   Copyright (c) Rich Hickey. All rights reserved.
 *   The use and distribution terms for this software are covered by the
 *   Eclipse Public License 1.0 (http://opensource.org/licenses/eclipse-1.0.php)
 *   which can be found in the file epl-v10.html at the root of this distribution.
 *   By using this software in any fashion, you are agreeing to be bound by
 * 	 the terms of this license.
 *   You must not remove this notice, or any other, from this software.
 **/

/* rich Aug 21, 2007 */

package clojure.lang;

import java.lang.ref.Reference;
import java.util.HashMap;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;
import java.net.URLClassLoader;
import java.net.URL;
import java.lang.ref.ReferenceQueue;
import java.lang.ref.SoftReference;
import java.io.InputStream;

public class DynamicClassLoader extends URLClassLoader{
HashMap<Integer, Object[]> constantVals = new HashMap<Integer, Object[]>();
static ConcurrentHashMap<String, Reference<Class>>classCache =
        new ConcurrentHashMap<String, Reference<Class> >();

static final URL[] EMPTY_URLS = new URL[]{};

static final ReferenceQueue rq = new ReferenceQueue();

public DynamicClassLoader(){
    //pseudo test in lieu of hasContextClassLoader()
	super(EMPTY_URLS,(Thread.currentThread().getContextClassLoader() == null ||
                Thread.currentThread().getContextClassLoader() == ClassLoader.getSystemClassLoader())?
                Compiler.class.getClassLoader():Thread.currentThread().getContextClassLoader());
}

public DynamicClassLoader(ClassLoader parent){
	super(EMPTY_URLS,parent);
}

/**
 * Entry point used by Clojure's Compiler to define a class from JVM bytecode.
 * The bytecode-to-class step is delegated to defineMissingClass so that
 * platform-specific subclasses (e.g. DalvikDynamicClassLoader on Android)
 * can translate JVM bytecode to DEX before loading.
 */
public Class defineClass(String name, byte[] bytes, Object srcForm){
	Util.clearCache(rq, classCache);
	Class c = defineMissingClass(name, bytes, srcForm);
    classCache.put(name, new SoftReference(c,rq));
    return c;
}

/**
 * Hook for subclasses to provide a platform-specific way of turning JVM
 * bytecode into a loaded Class. The default uses ClassLoader.defineClass
 * which is what standard JVMs require. Android subclasses override this
 * to translate the bytecode to DEX first.
 *
 * @since 1.13
 */
protected Class<?> defineMissingClass(String name, byte[] bytes, Object srcForm){
    return defineClass(name, bytes, 0, bytes.length);
}

static Class<?> findInMemoryClass(String name) {
    Reference<Class> cr = classCache.get(name);
	if(cr != null)
		{
		Class c = cr.get();
        if(c != null)
            return c;
		else
	        classCache.remove(name, cr);
		}
	return null;
}

protected Class<?>findClass(String name) throws ClassNotFoundException {
	Class c = findInMemoryClass(name);
	if (c != null)
		return c;
	else
		return super.findClass(name);
}

protected synchronized Class<?> loadClass(String name, boolean resolve) throws ClassNotFoundException {
	Class c = findLoadedClass(name);
	if (c == null) {
		c = findInMemoryClass(name);
		if (c == null)
			c = super.loadClass(name, false);
    }
	if (resolve)
		resolveClass(c);
	return c;
}

public void registerConstants(int id, Object[] val){
	constantVals.put(id, val);
}

public Object[] getConstants(int id){
	return constantVals.get(id);
}

public void addURL(URL url){
	super.addURL(url);
}

/**
 * Hook for subclasses to supply data_readers.clj from a platform-specific
 * place (e.g. Android assets). Default returns null so the standard
 * classpath enumeration path is used.
 *
 * @since 1.13
 */
public InputStream getDataReadersStream() {
    return null;
}

}
