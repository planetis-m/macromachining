import macros

proc transformState(node: NimNode, handlerProcs: seq[NimNode]) =
   expectKind(node, nnkCommand)
   let stateValue = node[1]
   expectKind(node[2], nnkStmtList)
   for n in node[2].children:
      case n.kind
      of nnkProcDef:
         if n.params.len < 2 or n.params[1][1].kind != nnkEmpty:
            error(n.params.lineInfo & ": Proc's 'this' parameter not found")
         block match:
            for handler in handlerProcs:
               if eqIdent(handler.name, n.name):
                  if not eqIdent(handler.params[1][0], n.params[1][0]):
                     error("Proc's 'this' parameter must match with the one in the action")
                  if handler.params.len != n.params.len or handler.params[0] != n.params[0]:
                     error("Proc's signature doesn't match with the action's")
                  # Add of branch to handler's body
                  expectKind(handler.body[0], nnkCaseStmt)
                  handler.body[0].add(nnkOfBranch.newTree(stateValue, n.body))
                  break match
            error("Proc's name doesn't match with any action")
      else:
         error(n.lineInfo & ": Invalid node: " & n.repr)

macro fsm*(head, body): untyped =
   result = newStmtList()
   var handlerProcs: seq[NimNode]
   expectKind(head, nnkDotExpr)
   let entityType = head[0]
   let stateVar = head[1]
   expectKind(body, nnkStmtList)
   for n in body.children:
      case n.kind
      of nnkProcDef:
         if n.params.len < 2 or n.params[1][1].kind != nnkEmpty:
            error(n.params.lineInfo & ": Action's 'this' parameter not found")
         n.params[1][1] = nnkVarTy.newTree(entityType)
         let thisVar = n.params[1][0]
         expectKind(n.body, nnkEmpty) # Only a proc signature
         n.body = newStmtList()
         # Add case currentState
         n.body.add(nnkCaseStmt.newTree(nnkDotExpr.newTree(thisVar, stateVar)))
         handlerProcs.add n
      of nnkCommand:
         if $n[0] != "state": error("Invalid command " & $n[0])
         assert handlerProcs.len > 0, "No actions declared"
         transformState(n, handlerProcs)
      else:
         error(n.lineInfo & ": Invalid node: " & n.repr)
   result.add handlerProcs
   echo result.repr

when isMainModule:
   fsm Miner.currentState:
      proc enter(miner)
      proc execute(miner)
      proc exit(miner)

      state EnterMineAndDigForNugget:
         proc enter(miner) =
            # if the miner is not already located at the goldmine, he must
            # change location to the gold mine
            if miner.location != Goldmine:
               echo(miner, ": Walkin' to the goldmine")
            miner.changeLocation(Goldmine)

         proc execute(miner) =
            # the miner digs for gold until he is carrying in excess of MaxNuggets. 
            # If he gets thirsty during his digging he packs up work for a while and 
            # changes state to go to the saloon for a whiskey.
            miner.addToGoldCarried(1)
            miner.increaseFatigue()
            echo(miner, ": Pickin' up a nugget")
            # if enough gold mined, go and put it in the bank
            if miner.pocketsFull():
               miner.changeState(VisitBankAndDepositGold)
            if miner.thirsty():
               miner.changeState(QuenchThirst)

         proc exit(miner) =
            echo(miner,
               ": Ah'm leavin' the goldmine with mah pockets full o' sweet gold")

      state GoHomeAndSleepTilRested:
         proc enter(miner) =
            if miner.location != Shack:
               echo(miner, ": Walkin' home")
               miner.changeLocation(Shack)

         proc execute(miner) =
            # if miner is not fatigued start to dig for nuggets again.
            if not miner.fatigued:
               echo(miner,
                  ": What a God darn fantastic nap! Time to find more gold")
               miner.changeState(EnterMineAndDigForNugget)
            else:
               # sleep
               miner.decreaseFatigue()
               echo(miner, ": ZZZZ... ")

         proc exit(miner) =
            echo(miner, ": Leaving the house")
