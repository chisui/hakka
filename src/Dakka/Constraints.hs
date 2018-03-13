{-# LANGUAGE TypeFamilies
           , PolyKinds
           , KindSignatures
           , ConstraintKinds
           , DataKinds
           , TypeOperators
           , PackageImports
           , UndecidableInstances
           , TypeApplications
           , RankNTypes
           , StandaloneDeriving
           , ExistentialQuantification
#-}
module Dakka.Constraints where

import "base" Data.Kind -- We need *, that can't be expressed in an import filter
import "base" Data.Typeable ( Typeable, cast )
import "base" Unsafe.Coerce ( unsafeCoerce ) -- used for 'downCast'
import "base" Data.Function ( on )

type family (e :: k) :∈ (l :: [k]) :: Constraint where
    e :∈ (e ': as) = ()
    e :∈ (a ': as) = e :∈ as

type family (e :: k) :∈! (l :: [k]) :: Constraint where
    e :∈! (e ': as) = e :∉ as
    e :∈! (a ': as) = e :∈ as

type family (e :: k) :∉ (l :: [k]) :: Constraint where
    e :∉ (a ': as) = (e :≠ a, e :∉ as)
    e :∉ '[] = ()

type family (l0 :: [k]) :⊆ (l1 :: [k]) :: Constraint where
    '[]       :⊆ l = ()
    (a ': as) :⊆ l = (a :∈ l, as :⊆ l)

type (:.) (g :: b -> c) (f :: a -> b) (t :: a) = g (f t)

type (a :: k) :≠ (b :: k) = (a `EqT` b) ~ 'False


type family (a :: k) `EqT` (b :: k) :: Bool where
    a `EqT` a = 'True
    a `EqT` b = 'False


type family (a :: k) `ImplementsAll` (c :: [k -> Constraint]) :: Constraint where
    a `ImplementsAll` (c ': cs) = (c a, a `ImplementsAll` cs)
    a `ImplementsAll` '[] = ()

type family (c :: k -> Constraint) `ImplementedByAll` (l :: [k]) :: Constraint where
    c `ImplementedByAll` (a ': as) = (c a, c `ImplementedByAll` as)
    c `ImplementedByAll` '[] = ()


type RichData a = (Typeable a, Eq a, Show a)

(=~=) :: (Typeable a, Typeable b, Eq a) => a -> b -> Bool
a =~= b = Just a == cast b

data ConstrainedDynamic (cs :: [* -> Constraint])
    = forall a. (a `ImplementsAll` cs) => CDyn a

liftConstrained :: (a :⊆ b) => (ConstrainedDynamic a -> c) -> ConstrainedDynamic b -> c
liftConstrained f = f . downCast 

downCast :: (b :⊆ a) => ConstrainedDynamic a -> ConstrainedDynamic b
downCast = unsafeCoerce -- removing constrains is nothing more than casting to it

instance ('[Typeable, Eq] :⊆ cs) => Eq (ConstrainedDynamic cs) where
    (==) = eq `on` downCast 
      where
        eq :: ConstrainedDynamic '[Typeable, Eq] -> ConstrainedDynamic '[Typeable, Eq] -> Bool
        eq (CDyn a) (CDyn b) = a =~= b

instance (Show :∈ cs) => Show (ConstrainedDynamic cs) where
    show = ("ConstrainedDynamic " ++) . liftConstrained @'[Show] (\ (CDyn a) -> show a)

type RichDynamic = ConstrainedDynamic '[Typeable, Eq, Show]
