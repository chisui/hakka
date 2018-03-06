{-# LANGUAGE FlexibleContexts
           , FlexibleInstances
           , TypeFamilies
           , MultiParamTypeClasses
           , FunctionalDependencies
           , DataKinds
           , ExistentialQuantification
           , GeneralizedNewtypeDeriving
           , StandaloneDeriving
           , DeriveDataTypeable
           , PackageImports
           , TypeOperators
           , ConstraintKinds
           , PolyKinds
           , RankNTypes
           , UndecidableInstances
           , UndecidableSuperClasses
#-}
module Dakka.Actor where

import "base" Data.Kind ( Constraint )
import "base" Data.Typeable ( Typeable, cast )
import "base" Data.Proxy ( Proxy(..) )

import "transformers" Control.Monad.Trans.State.Lazy ( StateT, execStateT )
import "transformers" Control.Monad.Trans.Writer.Lazy ( Writer, runWriter )
import "base" Control.Monad.IO.Class ( MonadIO( liftIO ) )

import "mtl" Control.Monad.State.Class ( MonadState, modify )
import "mtl" Control.Monad.Writer.Class ( MonadWriter( tell ) )

import Dakka.Constraints


-- | A path of an Actor inside the Actor system.
-- FIXME This is a Bullshit implementation
newtype Path a = Path Word
    deriving (Show, Eq, Typeable)

-- | Execution Context of an 'Actor'.
-- Has to provide ways to:
--
--     * change the state of an `Actor` (through `MonadState`)
--
--     * send messages to other actors
--
--     * create new actors.
-- 
class (Actor a, MonadState a m) => ActorContext (a :: *) (m :: * -> *) | m -> a where
    {-# MINIMAL self, create, (send | (!)) #-}

    -- | reference to the currently running 'Actor'
    self :: m (Path a)

    -- | Creates a new `Actor` of type 'b' with provided start state
    create :: (Actor b, b :∈ Creates a) => b -> m (Path b)

    -- | If the Actors state is a 'Monoid' no inital State has to be provided.
    create' :: (Actor b, b :∈ Creates a, Monoid b) => m (Path b)
    create' = create mempty

    -- | Send a message to another actor
    send :: Actor b => Path b -> Message b -> m ()
    send = (!)

    -- | Alias for 'send' to enable akka style inline send.
    (!) :: Actor b => Path b -> Message b -> m ()
    (!) = send

-- ---------------- --
-- MockActorContext --
-- ---------------- --

-- | Encapsulates a Message sent to an actor
data Envelope = forall a. Actor a => Envelope
    { to  :: Path a
    , msg :: Message a
    }
deriving instance Show Envelope


-- | Encapsulates the intent to create another actor.
data CreationIntent = forall a. Actor a => CreationIntent a
deriving instance Show CreationIntent

-- | An ActorContext that simply collects all state transitions, sent messages and creation intents.
newtype MockActorContext a v = MockActorContext
    (StateT a (Writer [Either Envelope CreationIntent]) v)
  deriving (Functor, Applicative, Monad, MonadState a, MonadWriter [Either Envelope CreationIntent])

instance Actor a => ActorContext a (MockActorContext a) where

    self = return $ Path 0

    create a = do
        tell [Right $ CreationIntent a]
        return $ Path 0
    
    p ! m = tell [Left $ Envelope p m]

-- | Execute a 'Behavior' in a 'MockActorContext'.
execMock :: MockActorContext a b -> a -> (a, [Either Envelope CreationIntent])
execMock (MockActorContext ctx) = runWriter . execStateT ctx

-- ------- --
--  Actor  --
-- ------- --

-- | A Behavior of an 'Actor' defines how an Actor reacts to a message given a specific state.
-- A Behavior may be executed in any 'ActorContext' that has all of the actors 'Capabillities'.
type Behavior a = forall m. (ActorContext a m, m `ImplementsAll` Capabillities a) => Message a -> m ()

-- | To be able to route values through an actor system these values have provide certain features.
type RichData a = (Show a, Eq a, Typeable a)

class (RichData a, RichData (Message a), Actor `ImplementedByAll` Creates a) => Actor (a :: *) where
    -- | List of all types of actors that this actor may create in its lifetime.
    type Creates a :: [*]
    type Creates a = '[]
  
    -- | Type of Message this Actor may recieve
    type Message a :: *

    -- | List of all additional Capabillities the ActorContext has to provide For this Actors Behavior.
    type Capabillities a :: [(* -> *) -> Constraint]
    type Capabillities a = '[]

    -- | This Actors behavior
    behavior :: Behavior a

-- | A pure 'Actor' is one that has no additional Capabillities besides what a 
-- 'ActorContext' provides.
type PureActor a = (Actor a, Capabillities a ~ '[])

-- | A leaf 'Actor' is one that doesn't create any children.
type LeafActor a = (Actor a, Creates a ~ '[])

behaviorOf :: Proxy a -> Behavior a 
behaviorOf = const behavior


-- -------- --
--   Test   --
-- -------- --

-- | Utillity function for equality of Typeables.
-- FIXME move to differenct module.
(=~=) :: (Typeable a, Typeable b, Eq a) => a -> b -> Bool
a =~= b = Just a == cast b

-- | Actor with all bells and whistles.
newtype TestActor = TestActor
    { i :: Int
    } deriving (Show, Eq, Typeable)
instance Actor TestActor where
  type Message TestActor = String
  type Creates TestActor = '[OtherActor]
  type Capabillities TestActor = '[MonadIO]
  behavior m = do
      modify (TestActor . succ . i)
      liftIO $ putStrLn m
      p <- create OtherActor
      p ! Msg m

-- | Actor with custom message type.
-- This one also communicates with another actor and expects a response.
newtype Msg = Msg String deriving (Show, Eq, Typeable)
instance Response Msg where
  toResponse = Msg
data OtherActor = OtherActor deriving (Show, Eq, Typeable)
instance Actor OtherActor where
  type Message OtherActor = Msg
  type Creates OtherActor = '[WithRef]
  behavior m = do
      p <- create WithRef
      a <- self
      p ! RefMsg a

-- | Actor that handles references to other Actors
class Response a where
  toResponse :: String -> a
data RefMsg = forall a. (Actor a, Response (Message a)) => RefMsg
    { ref :: Path a }
deriving instance Show RefMsg
deriving instance Typeable RefMsg
instance Eq RefMsg where
    (RefMsg a) == (RefMsg b) = a =~= b

data WithRef = WithRef deriving (Show, Eq, Typeable)
instance Actor WithRef where
    type Message WithRef = RefMsg
    behavior (RefMsg a) = do
        a ! toResponse "hello"

