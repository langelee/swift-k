/*
 * Created on Aug 13, 2007
 */
package org.griphyn.vdl.type.impl;

import java.net.URI;
import java.net.URISyntaxException;
import java.util.List;

import javax.xml.namespace.QName;

import org.griphyn.vdl.type.DuplicateFieldException;
import org.griphyn.vdl.type.Field;
import org.griphyn.vdl.type.Type;

public class UnresolvedType implements Type {
	private String name;
	private URI namespaceURI;
	private boolean array;
	
	public UnresolvedType(String namespace, String name, boolean array) {
		this.setNamespace(namespace);
		this.name = name;
		this.array = array;
	}
	
	public UnresolvedType(URI namespace, String name, boolean array) {
		this.setNamespace(namespace);
		this.name = name;
		this.array = array;
	}
	
	public UnresolvedType(String name, boolean array) {
		this.name = name;
		this.array = array;
	}

	public void addField(Field field) throws DuplicateFieldException {
		throw new UnsupportedOperationException();
	}

	public void addField(String name, Type type) throws DuplicateFieldException {
		throw new UnsupportedOperationException();
	}

	public Type arrayType() {
		throw new UnsupportedOperationException();
	}

	public Type getBaseType() {
		throw new UnsupportedOperationException();
	}

	public Field getField(String name) throws NoSuchFieldException {
		throw new UnsupportedOperationException();
	}

	public List getFieldNames() {
		throw new UnsupportedOperationException();
	}

	public List getFields() {
		throw new UnsupportedOperationException("addField");
	}

	public String getName() {
		return name;
	}

	public String getNamespace() {
		return namespaceURI.toString();
	}

	public URI getNamespaceURI() {
		return namespaceURI;
	}

	public QName getQName() {
		return new QName(namespaceURI.toString(), name);
	}

	public boolean isArray() {
		return array;
	}

	public boolean isPrimitive() {
		throw new UnsupportedOperationException();
	}

	public void setBaseType(Type base) {
		throw new UnsupportedOperationException();
	}

	public void setName(String name) {
		this.name = name;
	}

	public void setNamespace(String namespace) {
		if (namespace != null) {
			try {
				this.namespaceURI = new URI(namespace);
			}
			catch (URISyntaxException e) {
				throw new IllegalArgumentException(
						"The supplied namespace is not a valid URI string");
			}
		}
		else {
			this.namespaceURI = null;
		}
	}

	public void setNamespace(URI namespace) {
		this.namespaceURI = namespace;
	}

	public void setPrimitive() {
		throw new UnsupportedOperationException();
	}

	public void setQName(QName name) {
		this.name = name.getLocalPart();
		try {
			this.namespaceURI = new URI(name.getNamespaceURI());
		}
		catch (URISyntaxException e) {
			throw new IllegalArgumentException("The supplied namespace is not a valid URI string");
		}
	}
	
	public boolean equals(Object other) {
		if (other instanceof Type) {
			Type ot = (Type) other;
            URI ons = ot.getNamespaceURI();
            if ((namespaceURI == null || ons == null) && namespaceURI != ons) {
            	return false;   
            }
			return ot.getName().equals(name) && (array == ot.isArray());
		}
		else {
			return false;
		}
	}

	public int hashCode() {
		return name.hashCode() + (array ? 101 : 23);
	}
	
	public String toString() {
		StringBuffer sb = new StringBuffer();
		if (namespaceURI != null) {
			sb.append(namespaceURI.toString());
			sb.append(':');
		}
		sb.append(name);
		if (array) {
			sb.append("[]");
		}
		return sb.toString();
	}
}
