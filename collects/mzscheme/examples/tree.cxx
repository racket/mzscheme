/* Example demonstrating how to inject a C++ class into MzScheme's
   class world. 

   Since it uses C++, this one can be slightly tricky to compile.
   Specifying the linker as, say g++, ensures that the right
   C++ libraries get included:
     mzc --cc tree.cxx
     mzc --linker /usr/bin/g++ --ld tree.so tree.o

  Example use:
    (define tree% (load-extension "tree.so"))

    (define o (make-object tree% 10))
    (send o get-leaves) ; => 10
    (send o get-left) ; => #f

    (send o grow 2) ; grows new branches on the frontier
    (send o get-left) ; => #<object:tree%>
    (send (send o get-left) get-leaves) ; => 2

    (define apple-tree%
      (class tree% ()
        (inherit graft)
        (override
          ;; This `grow' drops branches and grows new ones
	  [grow (lambda (n)
                  (let ([l (make-object apple-tree%)]
		        [r (make-object apple-tree%)])
		    (graft l r)))])
	(sequence (super-init 1))))

    (define a (make-object apple-tree%))
    (send a get-leaves) ; => 1
    (send a grow)
    (send a get-left) ; => #<object:apple-tree%>

    (define o (make-object tree% 10))
    (define a (make-object apple-tree%))
    (send o graft a #f)
    (send o grow 1)   ; C++ calls apple-tree%'s `grow' for `a'
    (send a get-left) ; -> #<object:apple-tree>
*/

#include "escheme.h"

/**********************************************************/
/* The original C++ class: Tree                           */
/**********************************************************/

/* This kind of tree never grows or loses leaves. It only changes when
   it grows subtrees, or when subtrees are grafted onto it. We could
   derive new classes (in Scheme) for trees that can grow leaves and
   fruit. */

class Tree {
private:

  int refcount; /* Suppose the C++ class uses reference counting. */

public:

  /* Public fields: */
  Tree *left_branch, *right_branch;
  int leaves;

  void *user_data; /* The original class might not be this friendly,
		      but for simplicity we assume that it is. 
		      The alternative is to use a hash table. */

  Tree(int init_leaves) {
    left_branch = right_branch = NULL;
    leaves = init_leaves;
    refcount = 1;
    user_data = NULL;
  }

  virtual void Grow(int n) {
    if (left_branch)
      left_branch->Grow(n);
    else
      left_branch = new Tree(n);
    if (right_branch)
      right_branch->Grow(n);
    else
      right_branch = new Tree(n);
  }

  void Graft(Tree *left, Tree *right) {
    Drop(left_branch);
    Drop(right_branch);

    left_branch = left;
    right_branch = right;

    Add(left_branch);
    Add(right_branch);
  }

  /* Note that Graft is not overrideable in C++.
     In Scheme, we might override this method, but
     the C++ code never has to know since it never
     calls the Graft method itself. */

  /* Reference counting utils: */

  static void Add(Tree *t) {
    if (t)
      t->refcount++;
  }
  static void Drop(Tree *t) {
    if (t) {
      t->refcount--;
      if (!t->refcount)
	delete t;
    }
  }
};

/**********************************************************/
/* The glue class: mzTree (C++ calls to Scheme)           */
/**********************************************************/

/* The Scheme class value: */
static Scheme_Object *tree_class;
/* Generic for the overrideable method: */
static Scheme_Object *grow_method;

/* We keep a pointer to the Scheme object, and override the
   Grow method to (potentially) dispatch to Scheme. */

class mzTree : public Tree {
public:
  mzTree(int c) : Tree(c) { }

  virtual void Grow(int n) {
    /* Check whether the Scheme class for user_data is 
       actually a derived class that overrides `grow': */
    Scheme_Object *scmobj;
    Scheme_Object *overriding;

    /* Pointer to Scheme instance kept in user_data: */
    scmobj = (Scheme_Object *)user_data;

    /* Cache a generic to find the method quickly: */
    if (!grow_method) {
      scheme_register_extension_global(&grow_method, sizeof(grow_method));
      grow_method = scheme_get_generic_data(tree_class,
					    scheme_intern_symbol("grow"));
    }
    
    /* Look for an overriding `grow' method in scmobj: */
    overriding = scheme_apply_generic_data(grow_method,
					   scmobj,
					   0); /* 0 means return NULL
						  if not overridden */

    if (overriding) {
      /* Call Scheme-based overriding implementation: */
      Scheme_Object *argv[1];

      argv[0] = scheme_make_integer(n);
      _scheme_apply(overriding, 1, argv);
    } else {
      /* Grow is not overridden in Scheme: */
      Tree::Grow(n);
    }
  }
};

/**********************************************************/
/* The glue functions (Scheme calls to C++)               */
/**********************************************************/

/* Macro for accessing C++ object pointer from a Scheme object: */
#define SCHEME_CPP_OBJ(obj) (((Scheme_Class_Object *)(obj))->primdata)

/* Used for finalizing: */
void FreeTree(void *scmobj, void *t)
{
  Tree::Drop((Tree *)t);
}

Scheme_Object *Make_Tree(Scheme_Object *obj, int argc, Scheme_Object **argv)
{
  /* Unfortunately, init arity is not automatically checked: */
  if (argc != 1)
    scheme_wrong_count("tree% initialization", 1, 1, argc, argv);

  if (!SCHEME_INTP(argv[0]))
    scheme_wrong_type("tree% initialization", 
		      "fixnum", 
		      0, argc, argv);

  /* Create C++ instance, and remember pointer back to Scheme instance: */
  Tree *t = new mzTree(SCHEME_INT_VAL(argv[0]));
  t->user_data = obj;

  /* Store C++ pointer in Scheme object: */
  SCHEME_CPP_OBJ(obj) = t;

  /* Free C++ instance when the Scheme object is no longer referenced: */
  scheme_add_finalizer(obj, FreeTree, t);

  return obj;
}

Scheme_Object *Grow(Scheme_Object *obj, int argc, Scheme_Object **argv)
{
  Tree *t;
  int n;

  if (!SCHEME_INTP(argv[0]))
    scheme_wrong_type("tree%'s grow", 
		      "fixnum", 
		      0, argc, argv);
  n = SCHEME_INT_VAL(argv[0]);

  /* Extract the C++ pointer: */
  t = (Tree *)SCHEME_CPP_OBJ(obj);
  
  /* Call method (without override check): */
  t->Tree::Grow(n);
  
  return scheme_void;
}

Scheme_Object *Graft(Scheme_Object *obj, int argc, Scheme_Object **argv)
{
  Tree *t, *l, *r;

  if (!SCHEME_FALSEP(argv[0]) && !scheme_is_a(argv[0], tree_class))
    scheme_wrong_type("tree%'s graft", 
		      "tree% object or #f", 
		      0, argc, argv);
  if (!SCHEME_FALSEP(argv[1]) && !scheme_is_a(argv[1], tree_class))
    scheme_wrong_type("tree%'s graft", 
		      "tree% object or #f", 
		      1, argc, argv);

  /* Extract the C++ pointer for `this': */
  t = (Tree *)SCHEME_CPP_OBJ(obj);

  /* Extract the C++ pointers for the args: */
  l = (SCHEME_FALSEP(argv[0])
       ? (Tree *)NULL
       : (Tree *)SCHEME_CPP_OBJ(argv[0]));
  r = (SCHEME_FALSEP(argv[1])
       ? (Tree *)NULL
       : (Tree *)SCHEME_CPP_OBJ(argv[1]));
  
  /* Call method: */
  t->Graft(l, r);
  
  return scheme_void;
}

Scheme_Object *MarshalTree(Tree *t)
{
  if (!t)
    return scheme_false;
  else if (!t->user_data) {
    /* Object created in C++, not seen by Scheme, yet.
       Create a Scheme version of this object. */
    Scheme_Object *scmobj;

    /* Make Scheme object: */
    scmobj = scheme_make_uninited_object(tree_class);

    /* Link C++ and Scheme objects: */
    t->user_data = scmobj;
    SCHEME_CPP_OBJ(scmobj) = t;
    
    return scmobj;
  } else
    /* Get pointer back to Scheme: */
    return (Scheme_Object *)t->user_data;
}

Scheme_Object *Get_Left(Scheme_Object *obj, int argc, Scheme_Object **argv)
{
  Tree *t = (Tree *)SCHEME_CPP_OBJ(obj);
  
  return MarshalTree(t->left_branch);
}

Scheme_Object *Get_Right(Scheme_Object *obj, int argc, Scheme_Object **argv)
{ 
  Tree *t = (Tree *)SCHEME_CPP_OBJ(obj);
 
  return MarshalTree(t->right_branch);
}

Scheme_Object *Get_Leaves(Scheme_Object *obj, int argc, Scheme_Object **argv)
{
  Tree *t = (Tree *)SCHEME_CPP_OBJ(obj);
 
  return scheme_make_integer(t->leaves);
}

/**********************************************************/
/* Extension initialization: create the Scheme class      */
/**********************************************************/

Scheme_Object *scheme_initialize(Scheme_Env *env)
{
  scheme_register_extension_global(&tree_class, sizeof(tree_class));

  tree_class = scheme_make_class("tree%",    /* name */
				 NULL,       /* superclass */
				 Make_Tree,  /* init func */
				 5);         /* num methods */

  scheme_add_method_w_arity(tree_class, "grow",
			    Grow, 1, 1);
  scheme_add_method_w_arity(tree_class, "graft", 
			    Graft, 2, 2);

  scheme_add_method_w_arity(tree_class, "get-left",
			    Get_Left, 0, 0);
  scheme_add_method_w_arity(tree_class, "get-right",
			    Get_Right, 0, 0);
  scheme_add_method_w_arity(tree_class, "get-leaves",
			    Get_Leaves, 0, 0);

  scheme_made_class(tree_class);
  
  return tree_class;
}

Scheme_Object *scheme_reload(Scheme_Env *env)
{
  return tree_class;
}
