header {
package org.globus.swift.parser;

import org.antlr.stringtemplate.*;
import java.util.List;
import java.util.Iterator;
}

class SwiftScriptParser extends Parser;

options {
    k=2;
    codeGenMakeSwitchThreshold = 2;
    codeGenBitsetTestThreshold = 3;
    defaultErrorHandler=false;
}

{
protected StringTemplateGroup m_templates=null;
protected String currentFunctionName=null;

public void setTemplateGroup(StringTemplateGroup tempGroup) {
    m_templates = tempGroup;
}

StringTemplate template(String name) {
    return m_templates.getInstanceOf(name);
}

StringTemplate text(String t) {
    return new StringTemplate(m_templates,t);
}

String escape(String s) {
    String s1 = s.replaceAll("&", "&amp;");
    String s2 = s1.replaceAll("<", "&lt;");
    String s3 = s2.replaceAll(">", "&gt;");
    return s3;
}

String quote(String s) {
    return s.replaceAll("\"", "&quot;");
}

}

// The specification for a VDL program
program returns [StringTemplate code=template("program")]
    :
    (nsdecl[code])*        //namespace declaration
    (topLevelStatement[code])*
    EOF
    ;

nsdecl [StringTemplate code]
{StringTemplate ns=template("nsDef");}
    :   "namespace" (prefix:ID{ns.setAttribute("prefix", prefix.getText());})? uri:STRING_LITERAL SEMI
    {
      ns.setAttribute("uri", uri.getText());
      code.setAttribute("namespaces", ns);
      if (ns.getAttribute("prefix") == null)
         code.setAttribute("targetNS", ns.getAttribute("uri"));
    }
    ;

typedecl [StringTemplate code]
{StringTemplate r=template("typeDef");
 StringTemplate t=null;}
    :    "type" id:ID {    r.setAttribute("name", id.getText()); }
    (
        SEMI
        |
        (t=type
        {
           r.setAttribute("type", t);
        }
        SEMI
        )
        | structdecl[r]
    )
    {code.setAttribute("types", r);}
    ;

structdecl [StringTemplate code]
{StringTemplate e=null, e1=null, t=null;}
    :   LCURLY
    (t=type id:ID
    {
    e=template("memberdefinition");
    e.setAttribute("type", t);
    e.setAttribute("name", id.getText());
    }
    (LBRACK RBRACK {e.setAttribute("isArray", "true");})?
    { code.setAttribute("members", e); }
    (
        COMMA
        id1:ID
        {
        e1=template("memberdefinition");
        e1.setAttribute("type", t);
        e1.setAttribute("name", id1.getText());
        }
        (LBRACK RBRACK {e1.setAttribute("isArray", "true");})?
        { code.setAttribute("members", e1); }
    )*
    SEMI
    )*
    RCURLY
    (options {
       warnWhenFollowAmbig = false;
     }
    :SEMI
    )?
    ;

topLevelStatement[StringTemplate code]
{StringTemplate d=null;}

   :

// these are ll(1) and easy to predict

      typedecl[code]
    | d=ll1statement
       {
        code.setAttribute("statements",d);
       }

// these are non-declaration assign-like statements

    |   (predictAssignStat) => d=assignStat
       {
        code.setAttribute("statements",d);
       }


// they all begin with (id name)
    | (predictDeclaration) => declaration[code]

// more complicated function invocations
// note that function invocations can happen in above statements too
// this section is just the remaining more specialised invocations

    |   (procedurecallCode) => d=procedurecallCode
       {
        code.setAttribute("statements",d);
       }

    |   (procedurecallStatAssignManyReturnParam[code]) => procedurecallStatAssignManyReturnParam[code]

// this is a declaration, but not sorted out the predications yet to
// group it into a decl block
    | (predictProceduredecl) => d=proceduredecl {code.setAttribute("functions", d);}
    ;

predictDeclaration {StringTemplate x,y;} : x=type y=declarator ;

declaration [StringTemplate code]
{StringTemplate t=null, n=null;}
    : t=type
      n=declarator
    (
     (predictProcedurecallDecl) => procedurecallDecl[code, t, n]
    | (variableDecl[code,null,null]) => variableDecl[code, t, n]
    | (predictDatasetdecl) => datasetdecl[code, t, n]
    )
    ;

variableDecl [StringTemplate code, StringTemplate t, StringTemplate d]
{StringTemplate v1=null, v2=null, i1=null, i2=null;}
    :  (b1:LBRACK RBRACK)? i1=varInitializer

    {
        v1 = template("variable");
        v1.setAttribute("type", t);
        v1.setAttribute("name", d);
        if (b1 != null)
            v1.setAttribute("isArray", "true");
        if (i1 != null)
            v1.setAttribute("value", i1);
        code.setAttribute("statements", v1);
    }
    ( COMMA d=declarator (b2:LBRACK RBRACK)? i2=varInitializer
      {
            v2 = template("variable");
            v2.setAttribute("type", t);
            v2.setAttribute("name", d);
             if (b2 != null)
               v2.setAttribute("isArray", "true");
            if (i2 != null)
               v2.setAttribute("value", i2);
            code.setAttribute("statements", v2);
          }
    )*
    SEMI
    ;

declarator returns [StringTemplate code=null]
    :   id:ID {code=text(id.getText());}
    ;

varInitializer returns [StringTemplate code=null]
    :    ( ASSIGN code=expression )?
    ;

// This is an initializer used to set up an array.
// currently does not support nested array.
arrayInitializer returns [StringTemplate code=template("arrayInit")]
{StringTemplate e=null,from=null,to=null,step=null;}
    :    LBRACK
    (
     (expression COLON) =>
     (
      from=expression COLON to=expression (COLON step=expression)?
      {
        StringTemplate range=template("range");
        range.setAttribute("from", from);
        range.setAttribute("to", to);
        if (step != null)
        range.setAttribute("step", step);
        code.setAttribute("range", range);
      }
     )
     |
     (
      e=expression {code.setAttribute("elements", e);}
      (
        // CONFLICT: does a COMMA after an initializer start a new
      //           initializer or start the option ',' at end?
      //           ANTLR generates proper code by matching
      //             the comma as soon as possible.
        options {
          warnWhenFollowAmbig = false;
        } : COMMA e=expression {code.setAttribute("elements", e);}
      )*
      (COMMA)?
     )
    )?
    RBRACK
    ;

predictDatasetdecl: (LBRACK RBRACK)? LT;

datasetdecl [StringTemplate code, StringTemplate t, StringTemplate d]
{StringTemplate dataset=null, m=null;}
    :  (b1:LBRACK RBRACK)? LT (m=mappingdecl | f:STRING_LITERAL) GT SEMI
    {
       dataset=template("dataset");
       dataset.setAttribute("type", t);
       dataset.setAttribute("name", d);
       if (m!=null)
           dataset.setAttribute("mapping", m);
       else
           dataset.setAttribute("lfn", f.getText());
       if (b1 != null)
           dataset.setAttribute("isArray", "true");
       code.setAttribute("statements", dataset);
    }
    ;

mappingdecl returns [StringTemplate code=template("mapping")]
{StringTemplate p=null, d=null;}
    :  d=declarator {code.setAttribute("descriptor",d);} SEMI
       mapparamdecl[code]
    ;

mapparamdecl [StringTemplate code]
{StringTemplate p=null;}
    :  (  p=mapparam {code.setAttribute("params", p);}
          ( COMMA p=mapparam {code.setAttribute("params", p);} )*
      (COMMA)?
       )?
    ;

mapparam returns [StringTemplate code=template("mapParam")]
{StringTemplate n=null, v=null;}
    :  n=declarator ASSIGN v=mappingExpr
    {
        code.setAttribute("name", n);
        code.setAttribute("value", v);
    }
    ;

// this goes as far as the LCURLY so that we don't mistake it for
// a function invocation. with more thought can be made shorter, perhaps.
predictProceduredecl
{StringTemplate f=null;}
    :  ( LPAREN
        f=formalParameter
        (   COMMA f=formalParameter
        )*
        RPAREN )?
        id:ID LPAREN
        ( f=formalParameter
            (COMMA f=formalParameter)*
        )?
        RPAREN
         LCURLY
    ;
proceduredecl returns [StringTemplate code=template("function")]
{StringTemplate f=null;}
    :  ( LPAREN
        f=formalParameter
        {
        f.setAttribute("outlink", "true");
        code.setAttribute("outputs", f);
        }
        (   COMMA f=formalParameter
            {
            f.setAttribute("outlink", "true");
            code.setAttribute("outputs", f);
            }
        )*
        RPAREN )?
        id:ID {currentFunctionName=id.getText();} LPAREN
        (   f=formalParameter
            {
            code.setAttribute("inputs", f);
            }
            (   COMMA f=formalParameter
                {
                code.setAttribute("inputs", f);
                }
            )*
        )?
        RPAREN
         LCURLY
        (
        atomicBody[code]
        |
        compoundBody[code]
        )
        RCURLY
        {
        code.setAttribute("name", id.getText());
        currentFunctionName=null;
        }
    ;

formalParameter returns [StringTemplate code=template("parameter")]
{StringTemplate t=null,d=null,v=null;}
    :   t=type d=declarator
        {
        code.setAttribute("type", t);
        code.setAttribute("name", d);
        }
        (
        (LBRACK RBRACK {code.setAttribute("isArray", "true");})
        | (ASSIGN v=constant
          {
          String value = (String)v.getAttribute("value");
          if (v.getName().equals("sConst")) {
            v.removeAttribute("value");
             v.setAttribute("value", quote(value));
        }
          code.setAttribute("defaultv", v);
      })
    )?
    ;

type
  returns [StringTemplate code=null]
    :   code=builtInType
    |   id:ID
        {
        code=template("type_user_object");
        code.setAttribute("name", id.getText());
        }
    ;

builtInType returns [StringTemplate code=null]
    :    "int"   {code=template("type_int");}
    |   "string"  {code=template("type_string");}
    |   "float" {code=template("type_float");}
    |   "bool" {code=template("type_bool");}
    ;

compoundStat[StringTemplate code]
    :   LCURLY
    ( innerStatement[code] )*
        RCURLY
    ;

compoundBody[StringTemplate code]
    :    ( innerStatement[code] )*
    ;

innerStatement[StringTemplate code]
{StringTemplate s=null;}
    : (predictDeclaration) => declaration[code]
    |
    ((
       s=ll1statement
    |  (procedurecallCode) => s=procedurecallCode
    |  (predictAssignStat) => s=assignStat
    )
       {
        code.setAttribute("statements",s);
       })
    |  (procedurecallStatAssignManyReturnParam[code]) => procedurecallStatAssignManyReturnParam[code]
    ;

caseInnerStatement [StringTemplate statements]
{ StringTemplate code = null; }
    :
    (  code=ll1statement
    |  (procedurecallCode) => code=procedurecallCode
    |  (predictAssignStat) => code=assignStat
    ) {statements.setAttribute("statements",code);}
    |   (procedurecallStatAssignManyReturnParam[statements]) => procedurecallStatAssignManyReturnParam[statements]
    ;

// These are the statements that we can predict with ll(1) grammer
// i.e. with one token of lookahead
ll1statement returns [StringTemplate code=null]
    :
    code=ifStat
    | code=foreachStat
    | code=switchStat
    | code=iterateStat
    | code=whileStat
    | "continue" {code=template("continue");} SEMI
    | SEMI {code=template("blank");}
    ;

ifStat returns [StringTemplate code=template("if")]
{
  StringTemplate cond=null;
  StringTemplate body=template("statementList");
  StringTemplate els=template("statementList");
}
    :  "if" LPAREN cond=expression RPAREN
        {
        code.setAttribute("cond", cond);
        }
        compoundStat[body] {code.setAttribute("body", body);}
        (
          options {
              warnWhenFollowAmbig = false;
          }
          : "else"
          compoundStat[els] {code.setAttribute("els", els);}
        )?
    ;

foreachStat returns [StringTemplate code=template("foreach")]
{
  StringTemplate ds=null, t=null;
  StringTemplate body=template("statementList");
}
    :  "foreach" (t=type)? id:ID (COMMA indexId:ID)? "in" ds=expression
    {
        if (t != null) {
            throw new SemanticException("Type specification of foreach iteration variable no longer supported. Remove it and recompile.");
        }
        code.setAttribute("var", id.getText());
        code.setAttribute("in", ds);
        if (indexId != null) {
           code.setAttribute("index", indexId.getText());
        }
    }
    compoundStat[body] {code.setAttribute("body", body);}
    ;

whileStat returns [StringTemplate code=template("while")]
{
  StringTemplate cond=null;
  StringTemplate body=template("statementList");
}
    :  "while" LPAREN cond=expression RPAREN
    {
    code.setAttribute("cond", cond);
    }
    compoundStat[body] {code.setAttribute("body", body);}
    ;

iterateStat returns [StringTemplate code=template("iterate")]
{
  StringTemplate cond=null;
  StringTemplate body=template("statementList");
}
    :  "iterate" id:ID
    compoundStat[body] {code.setAttribute("body", body);}
    "until" LPAREN cond=expression RPAREN SEMI
    {
    code.setAttribute("var", id.getText());
    code.setAttribute("cond", cond);
    }
    ;

switchStat returns [StringTemplate code=template("switch")]
{
  StringTemplate cond=null, b=null;
}
    :    "switch" LPAREN cond=expression RPAREN
    {code.setAttribute("cond", cond);}
    LCURLY
    ( b = casesGroup {code.setAttribute("cases", b);} )*
    RCURLY
    ;

casesGroup returns [StringTemplate code=template("case")]
{StringTemplate b=null;}
    :    (    // CONFLICT: to which case group do the statements bind?
            //           ANTLR generates proper code: it groups the
            //           many "case"/"default" labels together then
            //           follows them with the statements
            options {
                greedy = true;
            }
            :
            aCase[code]
        )
        caseSList[code]
    ;

aCase [StringTemplate code]
{StringTemplate v=null;}
    :    (
          "case" v=expression {code.setAttribute("value", v);}
          | "default"
                )
        COLON
    ;

caseSList [StringTemplate code]
{StringTemplate s=null;}
    :    ( caseInnerStatement[code] )*
    ;

predictAssignStat
{StringTemplate x=null;}
    : x=identifier ASSIGN ;

assignStat returns [StringTemplate code=null]
{StringTemplate id=null;}
    :
    id=identifier
    ASSIGN
    (
      (predictProcedurecallAssign) => code=procedurecallCode
        { StringTemplate o = template("returnParam");
          o.setAttribute("name",id);
          code.setAttribute("outputs",o);
        }
    |
      code=variableAssign
      {
          code.setAttribute("lhs",id);
      }
    )
    ;

variableAssign returns [StringTemplate code=null]
{StringTemplate a=null, e=null, id=null;}
    :
    e=expression SEMI
        {
            code=template("assign");
            code.setAttribute("rhs", e);
        }
    ;

predictProcedurecallAssign
    : ID LPAREN ;

procedurecallCode returns [StringTemplate code=template("call")]
{StringTemplate f=null;}
    :
        procedureInvocation[code]
    ;

procedureInvocation [StringTemplate code]
{StringTemplate f=null;}
    :
        id:ID {code.setAttribute("func", id.getText());}
        LPAREN
        (   f=actualParameter
        {
        code.setAttribute("inputs", f);
        }
            (   COMMA f=actualParameter
                {
        code.setAttribute("inputs", f);
            }
            )*
        )?
        RPAREN
        SEMI
    ;

predictProcedurecallDecl : ASSIGN ID LPAREN ;

procedurecallDecl [StringTemplate container, StringTemplate type, StringTemplate decl]
{
StringTemplate code=template("call");
StringTemplate f=template("returnParam");

StringTemplate var = template("variable");
var.setAttribute("name", decl);
var.setAttribute("type", type);
container.setAttribute("statements", var);

StringTemplate declref=template("variableReference");
declref.setAttribute("name",decl);
f.setAttribute("name", declref);
code.setAttribute("outputs", f);
container.setAttribute("statements",code);

}
    :
        ASSIGN
        procedureInvocation[code]
    ;



procedurecallStatAssignManyReturnParam [StringTemplate s]
{ StringTemplate code=template("call"); StringTemplate f=null;
  StringTemplate var=null; }
    :
        LPAREN
        f=returnParameter
              {
          code.setAttribute("outputs", f);
          var = template("variable");
          if(f.getAttribute("type") != null) {
            StringTemplate nameST = (StringTemplate)f.getAttribute("name");
            var.setAttribute("name",nameST.getAttribute("name"));
            var.setAttribute("type",f.getAttribute("type"));
            s.setAttribute("statements",var);
          }
              }
              (   COMMA f=returnParameter
                  {
              code.setAttribute("outputs", f);
              var = template("variable");
          if(f.getAttribute("type") != null) {
            StringTemplate nameST = (StringTemplate)f.getAttribute("name");
            var.setAttribute("name",nameST.getAttribute("name"));
              var.setAttribute("type",f.getAttribute("type"));
              s.setAttribute("statements",var);
          }
              }
              )*
        RPAREN
        ASSIGN
        procedureInvocation[code]
        {
            s.setAttribute("statements",code);
        }
    ;

returnParameter returns [StringTemplate code=template("returnParam")]
{StringTemplate t=null, id=null, d=null;}
    :   (t=type{        code.setAttribute("type", t);})?
        id=identifier
        {
        code.setAttribute("name", id);
        }
        (
          (ASSIGN declarator)=>(ASSIGN d=declarator)
          {
          code.setAttribute("bind", d);
          }
        )?
    ;

actualParameter returns [StringTemplate code=template("actualParam")]
{StringTemplate d=null, id=null, ai=null;}
    :
    (
        (declarator ASSIGN)=> (d=declarator ASSIGN)
        {
             code.setAttribute("bind", d);
          }
    )?
    id=expression
    {
      code.setAttribute("value", id);
    }
    ;

atomicBody [StringTemplate code]
{StringTemplate app=null, svc=null;}
    :      app=appSpec
    {code.setAttribute("config",app);}
    ;

appSpec returns [StringTemplate code=template("app")]
{StringTemplate exec=null;}
    :  "app" LCURLY
    exec=declarator
    { code.setAttribute("exec", exec);}
    (
      appArg[code]
    )*
    SEMI RCURLY
    ;

appArg [StringTemplate code]
{StringTemplate arg=null;}
    :   arg=mappingExpr
    {code.setAttribute("arguments", arg);}
    |
    stdioArg[code]
    ;

mappingExpr returns [StringTemplate code=null]
{StringTemplate e=null;}
    :
    e = expression
    {
      code=template("mappingExpr");
      code.setAttribute("expr", e);
    }
    ;

functionInvocation returns [StringTemplate code=template("functionInvocation")]
{StringTemplate func=null, e=null;}
    :   AT (
    (declarator LPAREN) =>
    (func=declarator
     {
       code.setAttribute("name", func);
     }
     LPAREN
     (
     functionInvocationArgument[code]
     (
       COMMA
       functionInvocationArgument[code]
     )*)?
     RPAREN
    )
    |
    (e=identifier | (LPAREN e=identifier RPAREN) )
    {
      code.setAttribute("name", "filename");
      code.setAttribute("args", e);
    }
    )
    ;

functionInvocationArgument [StringTemplate code]
{StringTemplate e = null;}
    :
     e=expression
     {
      code.setAttribute("args", e);
     }
     ;

stdioArg [StringTemplate code]
{StringTemplate t=null,m=null;}
    :    ("stdin" {t=template("stdin");}
    |
    "stdout" {t=template("stdout");}
    |
    "stderr" {t=template("stderr");}
    )
    ASSIGN
    m=mappingExpr
    {
        t.setAttribute("content", m);
        code.setAttribute("stdio", t);
    }
    ;

expression returns [StringTemplate code=null]
    :   code=orExpr
    ;

orExpr returns [StringTemplate code=null]
{StringTemplate a,b;}
    :   code=andExpr
        (   OR b=andExpr
            {
            a = code;
            code=template("or");
            code.setAttribute("left", a);
            code.setAttribute("right", b);
            }
        )*
    ;

andExpr returns [StringTemplate code=null]
{StringTemplate a,b;}
    :   code=equalExpr
        (   AND b=equalExpr
            {
            a = code;
            code=template("and");
            code.setAttribute("left", a);
            code.setAttribute("right", b);
            }
        )*
    ;

equalExpr returns [StringTemplate code=null]
{
StringTemplate a,b=null;
Token op=null;
}
    :   code=condExpr
        (
           {op=LT(1);}
            ( EQ | NE ) b=condExpr
            {
            a = code;
            code=template("cond");
            code.setAttribute("op", escape(op.getText()));
            code.setAttribute("left", a);
            code.setAttribute("right", b);
            }
        )?
    ;

condExpr returns [StringTemplate code=null]
{
StringTemplate a,b=null;
Token op=null;
}
    :   code=additiveExpr
        (
        options {
        greedy = true;
        //warnWhenFollowAmbig = false;
        }
        :
           {op=LT(1);}
            ( LT | LE | GT | GE ) b=additiveExpr
            {
            a = code;
            code=template("cond");
            code.setAttribute("op", escape(op.getText()));
            code.setAttribute("left", a);
            code.setAttribute("right", b);
            }
        )?
    ;

additiveExpr returns [StringTemplate code=null]
{
StringTemplate a,b=null;
Token op=null;
}
    :   code=multiExpr
    (
        options {
        greedy = true;
        //warnWhenFollowAmbig = false;
        }
        :
            {op=LT(1);}
            ( PLUS | MINUS ) b=multiExpr
            {
            a = code;
            code=template("arith");
            code.setAttribute("op", escape(op.getText()));
            code.setAttribute("left", a);
            code.setAttribute("right", b);
            }
        )*
    ;

multiExpr returns [StringTemplate code=null]
{
StringTemplate a,b=null;
Token op=null;
}
    :   code=unaryExpr
    (
        options {
        greedy = true;
        //warnWhenFollowAmbig = false;
        }
        :
            {op=LT(1);}
            ( STAR | IDIV | FDIV | MOD ) b=unaryExpr
            {
            a = code;
            code=template("arith");
            code.setAttribute("op", escape(op.getText()));
            code.setAttribute("left", a);
            code.setAttribute("right", b);
            }
        )*
    ;

unaryExpr returns [StringTemplate code=null]
{StringTemplate u=null;}
    : MINUS u=unaryExpr
      {code=template("unaryNegation"); code.setAttribute("exp", u);}
    | PLUS u=unaryExpr // unary plus has no effect
      {code=u;}
    | NOT u=unaryExpr
      {code=template("not"); code.setAttribute("exp", u);}
    | code=primExpr
    ;

primExpr returns [StringTemplate code=null]
{StringTemplate id=null, exp=null;}
    : code=identifier
    | LPAREN exp=orExpr RPAREN { code=template("paren");
        code.setAttribute("exp", exp);}
    | code=constant
    | code=functionInvocation
    ;

// TODO - redo identifier parsing to fit in with the XML style
// that this patch introduces

// specifically, need the base ID to be distinct from all the
// other IDs

identifier returns [StringTemplate code=null]
{ 
  StringTemplate c=null;
  code=template("variableReference");
}
    :
    base:ID {code.setAttribute("name",base.getText());}
    // now we can have an unbounded sequence of
    // optional array index, then .ID

    (c=arrayIndex 
      {
         c.setAttribute("array",code);
         code=c;
      }
    )?
    (
      c=memberName {c.setAttribute("structure",code); code=c;}
      (c=arrayIndex
      {
         c.setAttribute("array",code);
         code=c;
      }
      )?
    )*

    ;


arrayIndex returns [StringTemplate code=null]
{StringTemplate e=null;}
    :
    LBRACK
    (e=expression | s:STAR)
    RBRACK
    {
      code=template("arraySubscript");
      if(e != null) code.setAttribute("subscript",e);
      if(s != null) {
        StringTemplate st = template("sConst");
        st.setAttribute("value","*");
        code.setAttribute("subscript",st);
      }
    }
    ;

memberName returns [StringTemplate code=null]
    :
    d:DOT (member:ID | s:STAR)
    {
      code=template("memberAccess");
      if(member != null) code.setAttribute("name",member.getText());
      if(s != null) code.setAttribute("name","*");
    }
    ;

constant returns [StringTemplate code=null]
    : i:INT_LITERAL
      {
        code=template("iConst");
        code.setAttribute("value",i.getText());
      }
    | d:FLOAT_LITERAL
      {
        code=template("fConst");
        code.setAttribute("value",d.getText());
      }
    | s:STRING_LITERAL
      {
        code=template("sConst");
        code.setAttribute("value",quote(s.getText()));
      }
    | t:"true"
      {
        code=template("bConst");
        code.setAttribute("value", t.getText());
      }
    | f:"false"
      {
        code=template("bConst");
        code.setAttribute("value", f.getText());
      }
    | n:"null"
      {
        code=template("null");
      }
    | code=arrayInitializer
    ;

// TODO ^^^^^^ array literal -- rename and rearrange the methods

class SwiftScriptLexer extends Lexer;

options {
    charVocabulary = '\1'..'\377';
    testLiterals=false;    // don't automatically test for literals
    k=2;
}

AT        :   "@" ;
PLUS    :   "+" ;
MINUS   :   '-' ;
FDIV        :   '/' ;
IDIV        :   "%/" ;
MOD        :   "%%" ;
EQ      :   "==" ;
NE        :   "!=" ;
LT      :   '<' ;
LE        :   "<=" ;
GT        :   ">" ;
GE        :   ">=";
ASSIGN  :   '=' ;
AND        :   "&&";
OR        :   "||";
NOT        :   "!";
LBRACK options { paraphrase = "'['"; }   :   '[' ;
RBRACK options { paraphrase = "']'"; }   :   ']' ;
LPAREN options { paraphrase = "'('"; } :   '(' ;
RPAREN options { paraphrase = "')'"; } :   ')' ;
LCURLY options { paraphrase = "'{'"; } :   '{' ;
RCURLY options { paraphrase = "'}'"; } :   '}' ;
SEMI options { paraphrase = "a semicolon"; } : ';' ;
COMMA   :   ',' ;
COLON    :   ':' ;
STAR    :   '*' ;

ID     options
        {
          paraphrase = "an identifier";
          testLiterals = true;
        }
    :
    ('a'..'z'|'A'..'Z'|'_') ('a'..'z'|'A'..'Z'|'0'..'9'|'_')*
    ;

// string literals
STRING_LITERAL
    :    '"'! (~('"'|'\n'|'\r'))* '"'!
//    :    '"'! (ESC|~('"'|'\\'|'\n'|'\r'))* '"'!
    ;

NUMBER
    :
    ( INTPART {_ttype=INT_LITERAL; }
      ('.' FLOATPART {_ttype=FLOAT_LITERAL; })?
      (EXPONENT {_ttype=FLOAT_LITERAL; })?
    )
    |
    ( '.' { _ttype=DOT; }
      ((FLOATPART {_ttype=FLOAT_LITERAL; })
      (EXPONENT)?)?
    )
    ;

protected INTPART : (ANYDIGIT)+;

protected ANYDIGIT : ('0'..'9');

protected FLOATPART : (ANYDIGIT)+;

protected EXPONENT : ('e'|'E') ('+'|'-')? (ANYDIGIT)+ ;

// white spaces
WS  :   (   ' '
        |   '\t'
        |   '\r'
        |   '\n' {newline();}
        )+
        { $setType(Token.SKIP); }
    ;

// Single-line comments, c style
SL_CCOMMENT
    :    "//"
        (~('\n'|'\r'))* ('\n'|'\r'('\n')?)
        {$setType(Token.SKIP); newline();}
    ;

// Single-line comments, shell style
SL_SCOMMENT
    :    "#"
        (~('\n'|'\r'))* ('\n'|'\r'('\n')?)
        {$setType(Token.SKIP); newline();}
    ;

// multiple-line comments
ML_COMMENT
    :    "/*"
        (
        options {
            generateAmbigWarnings=false;
        }
        :
            { LA(2)!='/' }? '*'
        |    '\r' '\n'        {newline();}
        |    '\r'            {newline();}
        |    '\n'            {newline();}
        |    ~('*'|'\n'|'\r')
        )*
        "*/"
        {$setType(Token.SKIP);}
    ;

// escape sequence
protected
ESC
    :    '\\'
    (    'n'
    |    'r'
    |    't'
    |    'b'
    |    'f'
    |    '"'
    |    '\''
    |    '\\'
    )
    ;

