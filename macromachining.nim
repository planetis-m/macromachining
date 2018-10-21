## Hierarchical FSM macro for Nim
## ==============================
## 
## The fsm macro allows writing an finite state machine using the State pattern.
## implementing that interface are defined using the ``state`` command inside
## the macro statement.
## It requires a typeless parameter, acting as the 'self' variable, to be
## declared in all procedures.
import macros

type
   FsmBuilder = ref object
      handlerProcs: seq[NimNode]
      stateVal, superStateVal: NimNode
      thisVar, stateVar: NimNode

proc transfSuperCall(node: NimNode; b: FsmBuilder): NimNode =
   template changeState(body, name, field, value) =
      body.add(nnkAsgn.newTree(nnkDotExpr.newTree(name, field), value))
   # takes into account only statement-based syntax
   case node.kind
   of nnkStmtList, nnkStmtListExpr, nnkBlockStmt, nnkBlockExpr, nnkWhileStmt,
         nnkForStmt, nnkIfExpr, nnkIfStmt, nnkTryStmt, nnkCaseStmt,
         nnkElifBranch, nnkElse, nnkElifExpr:
      result = copyNimNode(node)
      for n in node:
         result.add transfSuperCall(n, b)
   else:
      if node.kind == nnkCall and node[0].kind == nnkDotExpr and
            eqIdent(node[0][0], "super"):
         if node.len < 2 or not eqIdent(node[1], b.thisVar):
            error(node.lineInfo & ": Super call's 'this' argument not found")
         var params: seq[NimNode]
         for i in 1 ..< node.len:
            params.add node[i]
         let procName = node[0][1]
         result = newStmtList()
         # save the previous state in a temp
         let tempState = genSym(nskLet, "tempState")
         result.add newLetStmt(tempState, nnkDotExpr.newTree(b.thisVar, b.stateVar))
         # before entering super, change state to top state
         result.changeState(b.thisVar, b.stateVar, b.superStateVal)
         # calling 'super' method with the retrieved params
         result.add nnkCall.newTree(procName).add(params)
         # after exiting super, reset state to original
         result.changeState(b.thisVar, b.stateVar, tempState)
      else:
         result = copyNimTree(node)

proc transfState(node: NimNode, b: FsmBuilder) =
   if node.kind == nnkCommand and node[1].kind == nnkInfix and eqIdent(node[1][0], "of"):
      b.stateVal = node[1][1]
      b.superStateVal = node[1][2]
   else:
      error(node.lineInfo & ": Declare a hierarchy with: 'State' of 'SuperState'")
   # skips transformation of 'RootState'
   let isRootState = eqIdent(b.superStateVal, "RootState")
   expectKind(node[2], nnkStmtList)
   for n in node[2].children:
      case n.kind
      of nnkProcDef:
         if n.params.len < 2 or n.params[1][1].kind != nnkEmpty:
            error(n.params.lineInfo & ": Proc's 'this' parameter not found")
         if n.params[0].kind != nnkEmpty:
            error(n.lineInfo & ": Proc's return type must be empty")
         block match:
            for handler in b.handlerProcs:
               if eqIdent(handler.name, n.name):
                  if not eqIdent(handler.params[1][0], n.params[1][0]):
                     error(n.params.lineInfo & ": Proc's 'this' parameter must match with the one in the action")
                  # todo: restrict return type to nnkEmpty
                  if handler.params.len != n.params.len:
                     error(n.lineInfo & ": Proc's signature doesn't match with the action's")
                  b.thisVar = n.params[1][0]
                  # Add of branch to handler's body
                  expectKind(handler.body[0], nnkCaseStmt)
                  # search and transfrom super calls
                  let caseBody = if isRootState: n.body else: transfSuperCall(n.body, b)
                  handler.body[0].add(nnkOfBranch.newTree(b.stateVal, caseBody))
                  break match
            error(n.lineInfo & ": Proc's name doesn't match with any action")
      else:
         error(n.lineInfo & ": Invalid node: " & n.repr)

macro fsm*(head, body): untyped =
   result = newStmtList()
   let b = FsmBuilder()
   expectKind(head, nnkDotExpr)
   let entityType = head[0]
   b.stateVar = head[1]
   expectKind(body, nnkStmtList)
   for n in body.children:
      case n.kind
      of nnkProcDef:
         if n.params.len < 2 or n.params[1][1].kind != nnkEmpty:
            error(n.params.lineInfo & ": Action's 'this' parameter not found")
         if n.params[0].kind != nnkEmpty:
            error(n.lineInfo & ": Action's return type must be empty")
         n.params[1][1] = nnkVarTy.newTree(entityType)
         let thisVar = n.params[1][0]
         expectKind(n.body, nnkEmpty) # Only a proc signature
         n.body = newStmtList()
         # Add case currentState
         n.body.add(nnkCaseStmt.newTree(nnkDotExpr.newTree(thisVar, b.stateVar)))
         b.handlerProcs.add n
      of nnkCommand:
         if not eqIdent(n[0], "state"):
            error(n.lineInfo & ": Invalid command: " & $n[0])
         assert b.handlerProcs.len > 0, "No actions declared"
         transfState(n, b)
      else:
         error(n.lineInfo & ": Invalid node: " & n.repr)
   result.add b.handlerProcs
   echo result.repr

when isMainModule:
   type
      MinerState = enum
         EnterMineAndDigForNugget,
         GoHomeAndSleepTilRested,
         QuenchThirst,
         VisitBankAndDepositGold,
         BaseState

      Miner = object
         # a class defining a goldminer
         currentState: MinerState

   fsm Miner.currentState:
      proc enter(miner)
      proc execute(miner)
      proc exit(miner)

      state BaseState of RootState:
         proc enter(miner) =
            # Does not change its location
            discard

         proc execute(miner) =
            # If he gets thirsty he changes state to go to 
            # the saloon for a whiskey.
            if miner.thirsty():
               miner.changeState(QuenchThirst)

         proc exit(miner) =
            discard

      state EnterMineAndDigForNugget of BaseState:
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
            super.execute(miner)

         proc exit(miner) =
            echo(miner,
               ": Ah'm leavin' the goldmine with mah pockets full o' sweet gold")

      state GoHomeAndSleepTilRested of BaseState:
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
