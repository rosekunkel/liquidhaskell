 {#measures}
============

Recap
-----

1. <div class="fragment">**Refinements:** Types + Predicates</div>
2. <div class="fragment">**Subtyping:** SMT Implication</div>

<br>
<br>
<br>

<div class="fragment">
So far: only specify properties of *base values* (e.g. `Int`) ...
</div>

<br>

<div class="fragment">
How to specify properties of *structures*?
</div>


<div class="hidden">

\begin{code}

{-# LIQUID "--no-termination" #-}
{-# LIQUID "--full" #-}

module Measures where
import Prelude hiding ((!!), length)
import Language.Haskell.Liquid.Prelude

-- length      :: L a -> Int
-- (!)         :: L a -> Int -> a

infixr `C`
\end{code}

</div>


 {#meas}
====================

Measuring Data Types
--------------------

Measuring Data Types
====================


Example: Length of a List 
-------------------------

Given a type for lists:

<br>

\begin{code}
data L a = N | C a (L a)
\end{code}

<div class="fragment">
<br>

We can define the **length** as:

<br>

\begin{code}
{-@ measure size  :: (L a) -> Int
    size (N)      = 0
    size (C x xs) = (1 + size xs)  @-}
\end{code}

<div class="hidden">

\begin{code}
{-@ data L [size] a = N | C {hd :: a, tl :: L a } @-}
{-@ invariant {v: L a | 0 <= size v}              @-} 
\end{code}

</div>

Example: Length of a List 
-------------------------

\begin{spec}
{-@ measure size  :: (L a) -> Int
    size (N)      = 0
    size (C x xs) = 1 + size xs  @-}
\end{spec}

<br>

We **strengthen** data constructor types

<br>

\begin{spec} <div/>
data L a where 
  N :: {v: L a | size v = 0}
  C :: a -> t:_ -> {v:_| size v = 1 + size t}
\end{spec}

Measures Are Uninterpreted
--------------------------

\begin{spec} <br>
data L a where 
  N :: {v: L a | size v = 0}
  C :: a -> t:_ -> {v:_| size v = 1 + size t}
\end{spec}

<br>

`size` is an **uninterpreted function** in SMT logic

Measures Are Uninterpreted
--------------------------

<br>

In SMT, [uninterpreted function](http://fm.csl.sri.com/SSFT12/smt-euf-arithmetic.pdf) $f$ obeys **congruence** axiom:

<br>

$$\forall \overline{x}, \overline{y}. \overline{x} = \overline{y} \Rightarrow
f(\overline{x}) = f(\overline{y})$$

<br>

<div class="fragment">
Other properties of `size` asserted when typing **fold** & **unfold**
</div>

<br>

<div class="fragment">
Crucial for *efficient*, *decidable* and *predictable* verification.
</div>

Measures Are Uninterpreted
--------------------------

Other properties of `size` asserted when typing **fold** & **unfold**

<br>

<div class="fragment">
\begin{spec}**Fold**<br>
z = C x y     -- z :: {v | size v = 1 + size y}
\end{spec}
</div>

<br>

<div class="fragment">
\begin{spec}**Unfold**<br>
case z of 
  N     -> e1 -- z :: {v | size v = 0}
  C x y -> e2 -- z :: {v | size v = 1 + size y}
\end{spec}
</div>

Example: Using Measures
-----------------------

<br>
<br>

[DEMO: 001_Refinements.hs](../hs/001_Refinements.hs)



Multiple Measures
=================

 {#adasd}
---------

Can support *many* measures for a type


Ex: List Emptiness 
------------------

Measure describing whether a `List` is empty 

\begin{code}
{-@ measure isNull :: (L a) -> Prop
    isNull (N)      = true
    isNull (C x xs) = false           @-}
\end{code}

<br>

<div class="fragment">
LiquidHaskell **strengthens** data constructors

\begin{spec}
data L a where 
  N :: {v : L a | isNull v}
  C :: a -> L a -> {v:(L a) | not (isNull v)}
\end{spec}

</div>

Conjoining Refinements
----------------------

Data constructor refinements are **conjoined** 

\begin{spec} 
data L a where 
  N :: {v:L a |  size v = 0 
              && isNull v }
  C :: a 
    -> xs:L a 
    -> {v:L a |  size v = 1 + size xs 
              && not (isNull v)      }
\end{spec}

Multiple Measures: Sets and Duplicates
======================================

 {#elements}
------------

[DEMO: 01_Elements.hs](../hs/01_Elements.hs)

<!-- BEGIN CUT

Multiple Measures: Red-Black Trees
==================================

 {#asdad}
---------

<img src="../img/RedBlack.png" height=300px>

+ <div class="fragment">**Color Invariant:** `Red` nodes have `Black` children</div>
+ <div class="fragment">**Height Invariant:** Number of `Black` nodes equal on *all paths*</div>
<br>

Basic Type 
----------

\begin{spec}
data Tree a = Leaf 
            | Node Color a (Tree a) (Tree a)

data Color  = Red 
            | Black
\end{spec}

Color Invariant 
---------------

`Red` nodes have `Black` children

<div class="fragment">
\begin{spec}
measure isRB        :: Tree a -> Prop
isRB (Leaf)         = true
isRB (Node c x l r) = c=Red => (isB l && isB r)
                      && isRB l && isRB r
\end{spec}
</div>

<div class="fragment">
where 
\begin{spec}
measure isB         :: Tree a -> Prop 
isB (Leaf)          = true
isB (Node c x l r)  = c == Black 
\end{spec}
</div>

*Almost* Color Invariant 
------------------------

<br>

Color Invariant **except** at root. 

<br>

<div class="fragment">
\begin{spec}
measure isAlmost        :: Tree a -> Prop
isAlmost (Leaf)         = true
isAlmost (Node c x l r) = isRB l && isRB r
\end{spec}
</div>


Height Invariant
----------------

Number of `Black` nodes equal on **all paths**

<div class="fragment">
\begin{spec} 
measure isBH        :: RBTree a -> Prop
isBH (Leaf)         =  true
isBH (Node c x l r) =  bh l = bh r 
                    && isBH l && isBH r 
\end{spec}
</div>

<div class="fragment">

where

\begin{spec}
measure bh        :: RBTree a -> Int
bh (Leaf)         = 0
bh (Node c x l r) = bh l 
                  + if c = Red then 0 else 1
\end{spec}
</div>

Refined Type 
------------

\begin{spec}
-- Red-Black Trees
type RBT a  = {v:Tree a | isRB v && isBH v}

-- Almost Red-Black Trees
type ARBT a = {v:Tree a | isAlmost v && isBH v}
\end{spec}

<br>

[Details](https://github.com/ucsd-progsys/liquidhaskell/blob/master/tests/pos/RBTree.hs)


Measures vs. Index Types
========================

Decouple Property & Type 
------------------------

Unlike [indexed types](http://dl.acm.org/citation.cfm?id=270793) ...

<br>

<div class="fragment">

+ Measures **decouple** properties from structures

+ Support **multiple** properties over structures 

+ Enable  **reuse** of structures in different contexts                 

</div>

<br>

<div class="fragment">Invaluable in practice!</div>

END CUT -->

Recap
-----

<br>
<br>


1. Refinements: Types + Predicates
2. Subtyping: SMT Implication
3. **Measures:** Strengthened Constructors

<br>

<div class="fragment">Automatic Verification of Collections</div>

<br>
<br>

<div class="fragment"><a href="04_AbstractRefinements.lhs.slides.html" target="_blank">[continue]</a></div>