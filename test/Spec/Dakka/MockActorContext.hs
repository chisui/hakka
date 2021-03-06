{-# OPTIONS_GHC -fno-warn-orphans #-} -- Arbitrary
{-# LANGUAGE DataKinds            #-}
{-# LANGUAGE FlexibleContexts     #-}
{-# LANGUAGE FlexibleInstances    #-}
{-# LANGUAGE OverloadedStrings    #-}
{-# LANGUAGE PackageImports       #-}
{-# LANGUAGE ScopedTypeVariables  #-}
{-# LANGUAGE TypeApplications     #-}
{-# LANGUAGE TypeOperators        #-}
{-# LANGUAGE UndecidableInstances #-}
module Spec.Dakka.MockActorContext ( tests ) where

import           "mtl" Control.Monad.State.Class          (modify)

import           "tasty" Test.Tasty                       (TestTree, testGroup)
import           "tasty-hunit" Test.Tasty.HUnit           (testCase, (@=?))
import           "tasty-quickcheck" Test.Tasty.QuickCheck (testProperty, (===))

import           Spec.Dakka.Actor                         hiding (tests)

import           "dakka" Dakka.Actor.Internal
import           "dakka" Dakka.MockActorContext


type SomePath = ActorRef PlainMessageActor

somePath :: SomePath
somePath = ActorRef "0"


tests :: TestTree
tests = testGroup "Dakka.MockActorContext"
    [ testGroup "SystemMessage"
        [ testGroup "Show"
            [ testCase "Creates <<TrivialActor>>@\"id\"" $
                show (Creates (ActorRef @TrivialActor "id")) @=? "Creates (ActorRef <<TrivialActor>>@\"id\")"
            , testCase "Creates <<GenericActor Int>>" $
                show (Creates (ActorRef @(GenericActor Int) "id")) @=? "Creates (ActorRef <<GenericActor Int>>@\"id\")"
            , testCase "Send {to = (ctorRef <<TrivialActor>>@\"\"), msg = ()}" $
                show (Send (ActorRef @TrivialActor mempty) ())
                    @=? "Send {to = (ActorRef <<TrivialActor>>@\"\"), msg = ()}"
            ]
        , testGroup "Eq"
            [ testCase "Creates = Creates" $
                Creates (ActorRef @TrivialActor "") @=? Creates (ActorRef @TrivialActor "")
            , testProperty "Send a b = Send a b" $
                \ (a :: SomePath) (a' :: SomePath) b b' -> (Send a b == Send a' b') === (a == a' && b == b')
            ]
        ]
    , testGroup "MockActorContext"
        [ testGroup "ActorContext"
            [ testCase "self" $
                evalMock' self @=? somePath
            , testGroup "create"
                [ testCase "returns new path" $
                    evalMock' @CreatesActor (create @TrivialActor)
                        @=? ActorRef "1"
                , testCase "fires Create message" $
                    snd (execMock' @CreatesActor (create @TrivialActor)) @=? [Left (Creates (ActorRef @TrivialActor "1"))]
                ]
            , testCase "send" $
                snd (execMock' @PlainMessageActor (self >>= (! "hello"))) @=? [Right (Send somePath "hello")]
            ]
        , testGroup "MonadState"
            [ testCase "state" $
                fst (execMock' (modify (\ (CustomStateActor i) -> CustomStateActor (i+1))))
                    @=? CustomStateActor 1
            ]
        , testCase "runMock somePath (pure ()) PlainMessageActor = ((), (PlainMessageActor, []))" $
            runMock (pure ()) (mempty @PlainMessageActor) @=? ((), (mempty, []))
        ]
    ]

