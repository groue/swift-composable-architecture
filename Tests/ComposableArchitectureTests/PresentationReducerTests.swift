import ComposableArchitecture
import XCTest

#if swift(>=5.7)
  @MainActor
  final class PresentationReducerTests: XCTestCase {
    func testPresentation_parentDismissal() async {
      struct Child: ReducerProtocol {
        struct State: Equatable {
          var count = 0
        }
        enum Action: Equatable {
          case decrementButtonTapped
          case incrementButtonTapped
        }
        func reduce(into state: inout State, action: Action) -> EffectTask<Action> {
          switch action {
          case .decrementButtonTapped:
            state.count -= 1
            return .none
          case .incrementButtonTapped:
            state.count += 1
            return .none
          }
        } 
      }

      struct Parent: ReducerProtocol {
        struct State: Equatable {
          @PresentationState var child: Child.State?
        }
        enum Action: Equatable {
          case child(PresentationAction<Child.Action>)
          case presentChild
        }
        var body: some ReducerProtocol<State, Action> {
          Reduce { state, action in
            switch action {
            case .child:
              return .none
            case .presentChild:
              state.child = Child.State()
              return .none
            }
          }
          .presents(\.$child, action: /Action.child) {
            Child()
          }
        }
      }

      let store = TestStore(
        initialState: Parent.State(),
        reducer: Parent()
      )

      await store.send(.presentChild) {
        $0.child = Child.State()
      }
      await store.send(.child(.presented(.incrementButtonTapped))) {
        try (/.some).modify(&$0.child) {
          $0.count = 1
        }
      }
      await store.send(.child(.dismiss)) {
        $0.child = nil
      }
    }

    func testPresentation_childDismissal() async {
      struct Child: ReducerProtocol {
        struct State: Equatable {
          var count = 0
        }
        enum Action: Equatable {
          case closeButtonTapped
          case decrementButtonTapped
          case incrementButtonTapped
        }
        @Dependency(\.dismiss) var dismiss
        func reduce(into state: inout State, action: Action) -> EffectTask<Action> {
          switch action {
          case .closeButtonTapped:
            return .fireAndForget {
              await self.dismiss()
            }
          case .decrementButtonTapped:
            state.count -= 1
            return .none
          case .incrementButtonTapped:
            state.count += 1
            return .none
          }
        }
      }

      struct Parent: ReducerProtocol {
        struct State: Equatable {
          var lastCount: Int?
          @PresentationState var child: Child.State?
        }
        enum Action: Equatable {
          case child(PresentationAction<Child.Action>)
          case presentChild
        }
        var body: some ReducerProtocol<State, Action> {
          Reduce { state, action in
            switch action {
            case .child(.dismiss):
              state.lastCount = state.child?.count
              return .none
            case .child:
              return .none
            case .presentChild:
              state.child = Child.State()
              return .none
            }
          }
          .presents(\.$child, action: /Action.child) {
            Child()
          }
        }
      }

      let store = TestStore(
        initialState: Parent.State(),
        reducer: Parent()
      )

      await store.send(.presentChild) {
        $0.child = Child.State()
      }
      await store.send(.child(.presented(.decrementButtonTapped))) {
        try (/.some).modify(&$0.child) {
          $0.count = -1
        }
      }
      await store.send(.child(.presented(.closeButtonTapped)))
      await store.receive(.child(.dismiss)) {
        $0.child = nil
        $0.lastCount = -1
      }
    }

    @available(iOS 16, macOS 13, tvOS 16, watchOS 9, *)
    func testPresentation_parentDismissal_effects() async {
      await _withMainSerialExecutor {
        struct Child: ReducerProtocol {
          struct State: Equatable {
            var count = 0
          }
          enum Action: Equatable {
            case startButtonTapped
            case tick
          }
          @Dependency(\.continuousClock) var clock
          func reduce(into state: inout State, action: Action) -> EffectTask<Action> {
            switch action {
            case .startButtonTapped:
              return .run { send in
                for try await _ in clock.timer(interval: .seconds(1)) {
                  await send(.tick)
                }
              }
            case .tick:
              state.count += 1
              return .none
            }
          }
        }

        struct Parent: ReducerProtocol {
          struct State: Equatable {
            @PresentationState var child: Child.State?
          }
          enum Action: Equatable {
            case child(PresentationAction<Child.Action>)
            case presentChild
          }
          var body: some ReducerProtocol<State, Action> {
            Reduce { state, action in
              switch action {
              case .child:
                return .none
              case .presentChild:
                state.child = Child.State()
                return .none
              }
            }
            .presents(\.$child, action: /Action.child) {
              Child()
            }
          }
        }

        let clock = TestClock()
        let store = TestStore(
          initialState: Parent.State(),
          reducer: Parent()
        ) {
          $0.continuousClock = clock
        }

        await store.send(.presentChild) {
          $0.child = Child.State()
        }
        await store.send(.child(.presented(.startButtonTapped)))
        await clock.advance(by: .seconds(2))
        await store.receive(.child(.presented(.tick))) {
          try (/.some).modify(&$0.child) {
            $0.count = 1
          }
        }
        await store.receive(.child(.presented(.tick))) {
          try (/.some).modify(&$0.child) {
            $0.count = 2
          }
        }
        await store.send(.child(.dismiss)) {
          $0.child = nil
        }
      }
    }

    @available(iOS 16, macOS 13, tvOS 16, watchOS 9, *)
    func testPresentation_childDismissal_effects() async {
      await _withMainSerialExecutor {
        struct Child: ReducerProtocol {
          struct State: Equatable {
            var count = 0
          }
          enum Action: Equatable {
            case closeButtonTapped
            case startButtonTapped
            case tick
          }
          @Dependency(\.continuousClock) var clock
          @Dependency(\.dismiss) var dismiss
          func reduce(into state: inout State, action: Action) -> EffectTask<Action> {
            switch action {
            case .closeButtonTapped:
              return .fireAndForget {
                await self.dismiss()
              }

            case .startButtonTapped:
              return .run { send in
                for try await _ in clock.timer(interval: .seconds(1)) {
                  await send(.tick)
                }
              }
            case .tick:
              state.count += 1
              return .none
            }
          }
        }

        struct Parent: ReducerProtocol {
          struct State: Equatable {
            @PresentationState var child: Child.State?
          }
          enum Action: Equatable {
            case child(PresentationAction<Child.Action>)
            case presentChild
          }
          var body: some ReducerProtocol<State, Action> {
            Reduce { state, action in
              switch action {
              case .child:
                return .none
              case .presentChild:
                state.child = Child.State()
                return .none
              }
            }
            .presents(\.$child, action: /Action.child) {
              Child()
            }
          }
        }

        let clock = TestClock()
        let store = TestStore(
          initialState: Parent.State(),
          reducer: Parent()
        ) {
          $0.continuousClock = clock
        }

        await store.send(.presentChild) {
          $0.child = Child.State()
        }
        await store.send(.child(.presented(.startButtonTapped)))
        await clock.advance(by: .seconds(2))
        await store.receive(.child(.presented(.tick))) {
          try (/.some).modify(&$0.child) {
            $0.count = 1
          }
        }
        await store.receive(.child(.presented(.tick))) {
          try (/.some).modify(&$0.child) {
            $0.count = 2
          }
        }
        await store.send(.child(.presented(.closeButtonTapped)))
        await store.receive(.child(.dismiss)) {
          $0.child = nil
        }
      }
    }

    @available(iOS 16, macOS 13, tvOS 16, watchOS 9, *)
    func testPresentation_identifiableDismissal_effects() async {
      await _withMainSerialExecutor {
        struct Child: ReducerProtocol {
          struct State: Equatable, Identifiable {
            let id: UUID
            var count = 0
          }
          enum Action: Equatable {
            case startButtonTapped
            case tick
          }
          @Dependency(\.continuousClock) var clock
          func reduce(into state: inout State, action: Action) -> EffectTask<Action> {
            switch action {
            case .startButtonTapped:
              return .run { send in
                for try await _ in clock.timer(interval: .seconds(1)) {
                  await send(.tick)
                }
              }
            case .tick:
              state.count += 1
              return .none
            }
          }
        }

        struct Parent: ReducerProtocol {
          struct State: Equatable {
            @PresentationState var child: Child.State?
          }
          enum Action: Equatable {
            case child(PresentationAction<Child.Action>)
            case presentChild
          }
          @Dependency(\.uuid) var uuid
          var body: some ReducerProtocol<State, Action> {
            Reduce { state, action in
              switch action {
              case .child:
                return .none
              case .presentChild:
                state.child = Child.State(id: self.uuid())
                return .none
              }
            }
            .presents(\.$child, action: /Action.child) {
              Child()
            }
          }
        }

        let clock = TestClock()
        let store = TestStore(
          initialState: Parent.State(),
          reducer: Parent()
        ) {
          $0.continuousClock = clock
          $0.uuid = .incrementing
        }

        await store.send(.presentChild) {
          $0.child = Child.State(id: UUID(uuidString: "00000000-0000-0000-0000-000000000000")!)
        }
        await store.send(.child(.presented(.startButtonTapped)))
        await clock.advance(by: .seconds(2))
        await store.receive(.child(.presented(.tick))) {
          try (/.some).modify(&$0.child) {
            $0.count = 1
          }
        }
        await store.receive(.child(.presented(.tick))) {
          try (/.some).modify(&$0.child) {
            $0.count = 2
          }
        }
        await store.send(.presentChild) {
          $0.child = Child.State(id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!)
        }
        await clock.advance(by: .seconds(2))
        await store.send(.child(.dismiss)) {
          $0.child = nil
        }
      }
    }

    func testPresentation_requiresDismissal() async {
      struct Child: ReducerProtocol {
        struct State: Equatable {
          var count = 0
        }
        enum Action: Equatable {
          case decrementButtonTapped
          case incrementButtonTapped
        }
        func reduce(into state: inout State, action: Action) -> EffectTask<Action> {
          switch action {
          case .decrementButtonTapped:
            state.count -= 1
            return .none
          case .incrementButtonTapped:
            state.count += 1
            return .none
          }
        }
      }

      struct Parent: ReducerProtocol {
        struct State: Equatable {
          @PresentationState var child: Child.State?
        }
        enum Action: Equatable {
          case child(PresentationAction<Child.Action>)
          case presentChild
        }
        var body: some ReducerProtocol<State, Action> {
          Reduce { state, action in
            switch action {
            case .child:
              return .none
            case .presentChild:
              state.child = Child.State()
              return .none
            }
          }
          .presents(\.$child, action: /Action.child) {
            Child()
          }
        }
      }

      let store = TestStore(
        initialState: Parent.State(),
        reducer: Parent()
      )

      await store.send(.presentChild) {
        $0.child = Child.State()
      }
      await store.skipInFlightEffects(strict: true)
    }

    @available(iOS 15, macOS 12, tvOS 15, watchOS 8, *)
    func testInertPresentation() async {
      struct Parent: ReducerProtocol {
        struct State: Equatable {
          @PresentationState var alert: AlertState<Action.Alert>?
        }
        enum Action: Equatable {
          case alert(PresentationAction<Alert>)
          case presentAlert

          enum Alert: Equatable {}
        }
        var body: some ReducerProtocol<State, Action> {
          Reduce { state, action in
            switch action {
            case .alert:
              return .none
            case .presentAlert:
              state.alert = AlertState {
                TextState("Uh oh!")
              }
              return .none
            }
          }
          .presents(\.$alert, action: /Action.alert) {}
        }
      }

      let store = TestStore(
        initialState: Parent.State(),
        reducer: Parent()
      )

      await store.send(.presentAlert) {
        $0.alert = AlertState {
          TextState("Uh oh!")
        }
      }
    }

    @available(iOS 15, macOS 12, tvOS 15, watchOS 8, *)
    func testInertPresentation_dismissal() async {
      struct Parent: ReducerProtocol {
        struct State: Equatable {
          @PresentationState var alert: AlertState<Action.Alert>?
        }
        enum Action: Equatable {
          case alert(PresentationAction<Alert>)
          case presentAlert

          enum Alert: Equatable {}
        }
        var body: some ReducerProtocol<State, Action> {
          Reduce { state, action in
            switch action {
            case .alert:
              return .none
            case .presentAlert:
              state.alert = AlertState {
                TextState("Uh oh!")
              }
              return .none
            }
          }
          .presents(\.$alert, action: /Action.alert) {}
        }
      }

      let store = TestStore(
        initialState: Parent.State(),
        reducer: Parent()
      )

      await store.send(.presentAlert) {
        $0.alert = AlertState {
          TextState("Uh oh!")
        }
      }
      await store.send(.alert(.dismiss)) {
        $0.alert = nil
      }
    }

    @available(iOS 15, macOS 12, tvOS 15, watchOS 8, *)
    func testInertPresentation_automaticDismissal() async {
      struct Parent: ReducerProtocol {
        struct State: Equatable {
          @PresentationState var alert: AlertState<Action.Alert>?
          var isDeleted = false
        }
        enum Action: Equatable {
          case alert(PresentationAction<Alert>)
          case presentAlert

          enum Alert: Equatable {
            case deleteButtonTapped
          }
        }
        var body: some ReducerProtocol<State, Action> {
          Reduce { state, action in
            switch action {
            case .alert(.presented(.deleteButtonTapped)):
              state.isDeleted = true
              return .none
            case .alert:
              return .none
            case .presentAlert:
              state.alert = AlertState {
                TextState("Uh oh!")
              } actions: {
                ButtonState(role: .destructive, action: .deleteButtonTapped) {
                  TextState("Delete")
                }
              }
              return .none
            }
          }
          .presents(\.$alert, action: /Action.alert) {}
        }
      }

      let store = TestStore(
        initialState: Parent.State(),
        reducer: Parent()
      )

      await store.send(.presentAlert) {
        $0.alert = AlertState {
          TextState("Uh oh!")
        } actions: {
          ButtonState(role: .destructive, action: .deleteButtonTapped) {
            TextState("Delete")
          }
        }
      }
      await store.send(.alert(.presented(.deleteButtonTapped))) {
        $0.alert = nil
        $0.isDeleted = true
      }
    }

    func testPresentation_hydratedDestination_childDismissal() async {
      await _withMainSerialExecutor {
        struct Child: ReducerProtocol {
          struct State: Equatable {
            var count = 0
          }
          enum Action: Equatable {
            case closeButtonTapped
            case decrementButtonTapped
            case incrementButtonTapped
          }
          @Dependency(\.dismiss) var dismiss
          func reduce(into state: inout State, action: Action) -> EffectTask<Action> {
            switch action {
            case .closeButtonTapped:
              return .fireAndForget {
                await self.dismiss()
              }
            case .decrementButtonTapped:
              state.count -= 1
              return .none
            case .incrementButtonTapped:
              state.count += 1
              return .none
            }
          }
        }

        struct Parent: ReducerProtocol {
          struct State: Equatable {
            @PresentationState var child: Child.State?
          }
          enum Action: Equatable {
            case child(PresentationAction<Child.Action>)
            case presentChild
          }
          var body: some ReducerProtocol<State, Action> {
            Reduce { state, action in
              switch action {
              case .child:
                return .none
              case .presentChild:
                state.child = Child.State()
                return .none
              }
            }
            .presents(\.$child, action: /Action.child) {
              Child()
            }
          }
        }

        let store = TestStore(
          initialState: Parent.State(child: Child.State()),
          reducer: Parent()
        )

        await store.send(.child(.presented(.closeButtonTapped)))
        await store.receive(.child(.dismiss)) {
          $0.child = nil
        }
      }
    }

    @available(iOS 16, macOS 13, tvOS 16, watchOS 9, *)
    func testEnumPresentation() async {
      await _withMainSerialExecutor {
        struct Child: ReducerProtocol {
          struct State: Equatable, Identifiable {
            let id: UUID
            var count = 0
          }
          enum Action: Equatable {
            case closeButtonTapped
            case startButtonTapped
            case tick
          }
          @Dependency(\.continuousClock) var clock
          @Dependency(\.dismiss) var dismiss
          func reduce(into state: inout State, action: Action) -> EffectTask<Action> {
            switch action {
            case .closeButtonTapped:
              return .fireAndForget {
                await self.dismiss()
              }

            case .startButtonTapped:
              return .run { send in
                for try await _ in clock.timer(interval: .seconds(1)) {
                  await send(.tick)
                }
              }
            case .tick:
              state.count += 1
              return .none
            }
          }
        }

        struct Parent: ReducerProtocol {
          struct State: Equatable {
            @PresentationState var destination: Destinations.State?
            var isDeleted = false
          }
          enum Action: Equatable {
            case destination(PresentationAction<Destinations.Action>)
            case presentAlert
            case presentChild(id: UUID? = nil)
          }
          @Dependency(\.uuid) var uuid
          var body: some ReducerProtocol<State, Action> {
            Reduce { state, action in
              switch action {
              case .destination(.presented(.alert(.deleteButtonTapped))):
                state.isDeleted = true
                return .none
              case .destination:
                return .none
              case .presentAlert:
                state.destination = .alert(
                  AlertState {
                    TextState("Uh oh!")
                  } actions: {
                    ButtonState(role: .destructive, action: .deleteButtonTapped) {
                      TextState("Delete")
                    }
                  }
                )
                return .none
              case let .presentChild(id):
                state.destination = .child(Child.State(id: id ?? self.uuid()))
                return .none
              }
            }
            .presents(\.$destination, action: /Action.destination) {
              Destinations()
            }
          }
          struct Destinations: ReducerProtocol {
            enum State: Equatable {
              case alert(AlertState<Action.Alert>)
              case child(Child.State)
            }
            enum Action: Equatable {
              case alert(Alert)
              case child(Child.Action)

              enum Alert: Equatable {
                case deleteButtonTapped
              }
            }
            var body: some ReducerProtocol<State, Action> {
              Scope(state: /State.alert, action: /Action.alert) {}
              Scope(state: /State.child, action: /Action.child) {
                Child()
              }
            }
          }
        }

        let clock = TestClock()
        let store = TestStore(
          initialState: Parent.State(),
          reducer: Parent()
        ) {
          $0.continuousClock = clock
          $0.uuid = .incrementing
        }

        await store.send(.presentChild()) {
          $0.destination = .child(
            Child.State(id: UUID(uuidString: "00000000-0000-0000-0000-000000000000")!)
          )
        }
        await store.send(.destination(.presented(.child(.startButtonTapped))))
        await clock.advance(by: .seconds(2))
        await store.receive(.destination(.presented(.child(.tick)))) {
          try (/Parent.Destinations.State.child).modify(&$0.destination) {
            $0.count = 1
          }
        }
        await store.receive(.destination(.presented(.child(.tick)))) {
          try (/Parent.Destinations.State.child).modify(&$0.destination) {
            $0.count = 2
          }
        }
        await store.send(.destination(.presented(.child(.closeButtonTapped))))
        await store.receive(.destination(.dismiss)) {
          $0.destination = nil
        }
        await store.send(.presentChild()) {
          $0.destination = .child(
            Child.State(id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!)
          )
        }
        await clock.advance(by: .seconds(2))
        await store.send(.destination(.presented(.child(.startButtonTapped))))
        await clock.advance(by: .seconds(2))
        await store.receive(.destination(.presented(.child(.tick)))) {
          try (/Parent.Destinations.State.child).modify(&$0.destination) {
            $0.count = 1
          }
        }
        await store.receive(.destination(.presented(.child(.tick)))) {
          try (/Parent.Destinations.State.child).modify(&$0.destination) {
            $0.count = 2
          }
        }
        await store.send(
          .presentChild(id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!)
        ) {
          try (/Parent.Destinations.State.child).modify(&$0.destination) {
            $0.count = 0
          }
        }
        await clock.advance(by: .seconds(2))
        await store.receive(.destination(.presented(.child(.tick)))) {
          try (/Parent.Destinations.State.child).modify(&$0.destination) {
            $0.count = 1
          }
        }
        await store.receive(.destination(.presented(.child(.tick)))) {
          try (/Parent.Destinations.State.child).modify(&$0.destination) {
            $0.count = 2
          }
        }
        await store.send(.presentAlert) {
          $0.destination = .alert(
            AlertState {
              TextState("Uh oh!")
            } actions: {
              ButtonState(role: .destructive, action: .deleteButtonTapped) {
                TextState("Delete")
              }
            }
          )
        }
        await store.send(.destination(.presented(.alert(.deleteButtonTapped)))) {
          $0.destination = nil
          $0.isDeleted = true
        }
      }
    }

    func testNavigation_cancelID_childCancellation() async {
      struct Child: ReducerProtocol {
        struct State: Equatable {}
        enum Action: Equatable {
          case startButtonTapped
          case stopButtonTapped
        }
        func reduce(into state: inout State, action: Action) -> EffectTask<Action> {
          switch action {
          case .startButtonTapped:
            return .fireAndForget {
              try await Task.never()
            }
            .cancellable(id: 42)

          case .stopButtonTapped:
            return .cancel(id: 42)
          }
        }
      }

      struct Parent: ReducerProtocol {
        struct State: Equatable {
          @PresentationState var child: Child.State?
        }
        enum Action: Equatable {
          case child(PresentationAction<Child.Action>)
          case presentChild
        }
        var body: some ReducerProtocol<State, Action> {
          Reduce { state, action in
            switch action {
            case .child:
              return .none
            case .presentChild:
              state.child = Child.State()
              return .none
            }
          }
          .presents(\.$child, action: /Action.child) {
            Child()
          }
        }
      }

      let store = TestStore(
        initialState: Parent.State(),
        reducer: Parent()
      )
      let presentationTask = await store.send(.presentChild) {
        $0.child = Child.State()
      }
      await store.send(.child(.presented(.startButtonTapped)))
      await store.send(.child(.presented(.stopButtonTapped)))
      await presentationTask.cancel()
    }

    func testNavigation_cancelID_parentCancellation() async {
      struct Grandchild: ReducerProtocol {
        struct State: Equatable {}
        enum Action: Equatable {
          case startButtonTapped
        }
        enum CancelID { case effect }
        func reduce(into state: inout State, action: Action) -> EffectTask<Action> {
          switch action {
          case .startButtonTapped:
            return .fireAndForget {
              try await Task.never()
            }
            .cancellable(id: CancelID.effect)
          }
        }
      }

      struct Child: ReducerProtocol {
        struct State: Equatable {
          @PresentationState var grandchild: Grandchild.State?
        }
        enum Action: Equatable {
          case grandchild(PresentationAction<Grandchild.Action>)
          case presentGrandchild
          case startButtonTapped
        }
        enum CancelID { case effect }
        var body: some ReducerProtocolOf<Self> {
          Reduce { state, action in
            switch action {
            case .grandchild:
              return .none
            case .presentGrandchild:
              state.grandchild = Grandchild.State()
              return .none
            case .startButtonTapped:
              return .fireAndForget {
                try await Task.never()
              }
              .cancellable(id: CancelID.effect)
            }
          }
          .presents(\.$grandchild, action: /Action.grandchild) {
            Grandchild()
          }
        }
      }

      struct Parent: ReducerProtocol {
        struct State: Equatable {
          @PresentationState var child: Child.State?
        }
        enum Action: Equatable {
          case child(PresentationAction<Child.Action>)
          case stopButtonTapped
          case presentChild
        }
        var body: some ReducerProtocol<State, Action> {
          Reduce { state, action in
            switch action {
            case .child:
              return .none
            case .stopButtonTapped:
              return .merge(
                .cancel(id: Child.CancelID.effect),
                .cancel(id: Grandchild.CancelID.effect)
              )
            case .presentChild:
              state.child = Child.State()
              return .none
            }
          }
          .presents(\.$child, action: /Action.child) {
            Child()
          }
        }
      }

      let store = TestStore(
        initialState: Parent.State(),
        reducer: Parent()
      )
      let childPresentationTask = await store.send(.presentChild) {
        $0.child = Child.State()
      }
      let grandchildPresentationTask = await store.send(.child(.presented(.presentGrandchild))) {
        $0.child?.grandchild = Grandchild.State()
      }
      await store.send(.child(.presented(.startButtonTapped)))
      await store.send(.child(.presented(.grandchild(.presented(.startButtonTapped)))))
      await store.send(.stopButtonTapped)
      await grandchildPresentationTask.cancel()
      await childPresentationTask.cancel()
    }

    @available(iOS 16, macOS 13, tvOS 16, watchOS 9, *)
    func testNavigation_cancelID_parentCancelTwoChildren() async {
      struct Child: ReducerProtocol {
        struct State: Equatable {
          var count = 0
        }
        enum Action: Equatable {
          case response(Int)
          case startButtonTapped
        }
        enum CancelID { case effect }
        @Dependency(\.continuousClock) var clock
        func reduce(into state: inout State, action: Action) -> EffectTask<Action> {
          switch action {
          case let .response(value):
            state.count = value
            return .none
          case .startButtonTapped:
            return .run { send in
              for await _ in self.clock.timer(interval: .seconds(1)) {
                await send(.response(42))
              }
            }
            .cancellable(id: CancelID.effect)
          }
        }
      }

      struct Parent: ReducerProtocol {
        struct State: Equatable {
          @PresentationState var child1: Child.State?
          @PresentationState var child2: Child.State?
        }
        enum Action: Equatable {
          case child1(PresentationAction<Child.Action>)
          case child2(PresentationAction<Child.Action>)
          case stopButtonTapped
          case presentChildren
        }
        var body: some ReducerProtocol<State, Action> {
          Reduce { state, action in
            switch action {
            case .child1, .child2:
              return .none
            case .stopButtonTapped:
              return .cancel(id: Child.CancelID.effect)
            case .presentChildren:
              state.child1 = Child.State()
              state.child2 = Child.State()
              return .none
            }
          }
          .presents(\.$child1, action: /Action.child1) {
            Child()
          }
          .presents(\.$child2, action: /Action.child2) {
            Child()
          }
        }
      }

      await _withMainSerialExecutor {
        let clock = TestClock()
        let store = TestStore(
          initialState: Parent.State(),
          reducer: Parent()
        ) {
          $0.continuousClock = clock
        }
        await store.send(.presentChildren) {
          $0.child1 = Child.State()
          $0.child2 = Child.State()
        }
        await store.send(.child1(.presented(.startButtonTapped)))
        await clock.advance(by: .seconds(1))
        await store.receive(.child1(.presented(.response(42)))) {
          $0.child1?.count = 42
        }
        await store.send(.child2(.presented(.startButtonTapped)))
        await clock.advance(by: .seconds(1))
        await store.receive(.child1(.presented(.response(42))))
        await store.receive(.child2(.presented(.response(42)))) {
          $0.child2?.count = 42
        }
        await store.send(.stopButtonTapped)
        await clock.run()
        await store.send(.child1(.dismiss)) {
          $0.child1 = nil
        }
        await store.send(.child2(.dismiss)) {
          $0.child2 = nil
        }
      }
    }

    @available(iOS 16, macOS 13, tvOS 16, watchOS 9, *)
    func testNavigation_cancelID_childCannotCancelSibling() async throws {
      struct Child: ReducerProtocol {
        struct State: Equatable {
          var count = 0
        }
        enum Action: Equatable {
          case response(Int)
          case startButtonTapped
          case stopButtonTapped
        }
        enum CancelID { case effect }
        @Dependency(\.continuousClock) var clock
        func reduce(into state: inout State, action: Action) -> EffectTask<Action> {
          switch action {
          case let .response(value):
            state.count = value
            return .none
          case .startButtonTapped:
            return .run { send in
              for await _ in self.clock.timer(interval: .seconds(1)) {
                await send(.response(42))
              }
            }
            .cancellable(id: CancelID.effect)
          case .stopButtonTapped:
            return .cancel(id: CancelID.effect)
          }
        }
      }

      struct Parent: ReducerProtocol {
        struct State: Equatable {
          @PresentationState var child1: Child.State?
          @PresentationState var child2: Child.State?
        }
        enum Action: Equatable {
          case child1(PresentationAction<Child.Action>)
          case child2(PresentationAction<Child.Action>)
          case presentChildren
        }
        var body: some ReducerProtocol<State, Action> {
          Reduce { state, action in
            switch action {
            case .child1, .child2:
              return .none
            case .presentChildren:
              state.child1 = Child.State()
              state.child2 = Child.State()
              return .none
            }
          }
          .presents(\.$child1, action: /Action.child1) {
            Child()
          }
          .presents(\.$child2, action: /Action.child2) {
            Child()
          }
        }
      }

      await _withMainSerialExecutor {
        let clock = TestClock()
        let store = TestStore(
          initialState: Parent.State(),
          reducer: Parent()
        ) {
          $0.continuousClock = clock
        }
        await store.send(.presentChildren) {
          $0.child1 = Child.State()
          $0.child2 = Child.State()
        }
        await store.send(.child1(.presented(.startButtonTapped)))
        await clock.advance(by: .seconds(1))
        await store.receive(.child1(.presented(.response(42)))) {
          $0.child1?.count = 42
        }
        await store.send(.child2(.presented(.startButtonTapped)))
        await clock.advance(by: .seconds(1))
        await store.receive(.child1(.presented(.response(42))))
        await store.receive(.child2(.presented(.response(42)))) {
          $0.child2?.count = 42
        }

        await store.send(.child1(.presented(.stopButtonTapped)))
        await clock.advance(by: .seconds(1))
        await store.receive(.child2(.presented(.response(42))))

        await store.send(.child2(.presented(.stopButtonTapped)))
        await clock.advance(by: .seconds(1))

        await clock.run()
        await store.send(.child1(.dismiss)) {
          $0.child1 = nil
        }
        await store.send(.child2(.dismiss)) {
          $0.child2 = nil
        }
      }
    }

    @available(iOS 16, macOS 13, tvOS 16, watchOS 9, *)
    func testNavigation_cancelID_childCannotCancelIdentifiableSibling() async throws {
      struct Child: ReducerProtocol {
        struct State: Equatable, Identifiable {
          let id: UUID
          var count = 0
        }
        enum Action: Equatable {
          case response(Int)
          case startButtonTapped
          case stopButtonTapped
        }
        enum CancelID { case effect }
        @Dependency(\.continuousClock) var clock
        func reduce(into state: inout State, action: Action) -> EffectTask<Action> {
          switch action {
          case let .response(value):
            state.count = value
            return .none
          case .startButtonTapped:
            return .run { send in
              for await _ in self.clock.timer(interval: .seconds(1)) {
                await send(.response(42))
              }
            }
            .cancellable(id: CancelID.effect)
          case .stopButtonTapped:
            return .cancel(id: CancelID.effect)
          }
        }
      }

      struct Parent: ReducerProtocol {
        struct State: Equatable {
          @PresentationState var child1: Child.State?
          @PresentationState var child2: Child.State?
        }
        enum Action: Equatable {
          case child1(PresentationAction<Child.Action>)
          case child2(PresentationAction<Child.Action>)
          case presentChildren
        }
        @Dependency(\.uuid) var uuid
        var body: some ReducerProtocol<State, Action> {
          Reduce { state, action in
            switch action {
            case .child1, .child2:
              return .none
            case .presentChildren:
              state.child1 = Child.State(id: self.uuid())
              state.child2 = Child.State(id: self.uuid())
              return .none
            }
          }
          .presents(\.$child1, action: /Action.child1) {
            Child()
          }
          .presents(\.$child2, action: /Action.child2) {
            Child()
          }
        }
      }

      await _withMainSerialExecutor {
        let clock = TestClock()
        let store = TestStore(
          initialState: Parent.State(),
          reducer: Parent()
        ) {
          $0.continuousClock = clock
          $0.uuid = .incrementing
        }
        await store.send(.presentChildren) {
          $0.child1 = Child.State(id: UUID(uuidString: "00000000-0000-0000-0000-000000000000")!)
          $0.child2 = Child.State(id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!)
        }
        await store.send(.child1(.presented(.startButtonTapped)))
        await clock.advance(by: .seconds(1))
        await store.receive(.child1(.presented(.response(42)))) {
          $0.child1?.count = 42
        }
        await store.send(.child2(.presented(.startButtonTapped)))
        await clock.advance(by: .seconds(1))
        await store.receive(.child1(.presented(.response(42))))
        await store.receive(.child2(.presented(.response(42)))) {
          $0.child2?.count = 42
        }

        await store.send(.child1(.presented(.stopButtonTapped)))
        await clock.advance(by: .seconds(1))
        await store.receive(.child2(.presented(.response(42))))

        await store.send(.child2(.presented(.stopButtonTapped)))
        await clock.advance(by: .seconds(1))

        await clock.run()
        await store.send(.child1(.dismiss)) {
          $0.child1 = nil
        }
        await store.send(.child2(.dismiss)) {
          $0.child2 = nil
        }
      }
    }
    @available(iOS 16, macOS 13, tvOS 16, watchOS 9, *)
    func testNavigation_cancelID_childCannotCancelParent() async {
      struct Child: ReducerProtocol {
        struct State: Equatable {}
        enum Action: Equatable {
          case stopButtonTapped
        }
        func reduce(into state: inout State, action: Action) -> EffectTask<Action> {
          switch action {
          case .stopButtonTapped:
            return .cancel(id: Parent.CancelID.effect)
          }
        }
      }

      struct Parent: ReducerProtocol {
        struct State: Equatable {
          @PresentationState var child: Child.State?
          var count = 0
        }
        enum Action: Equatable {
          case child(PresentationAction<Child.Action>)
          case presentChild
          case response(Int)
          case startButtonTapped
          case stopButtonTapped
        }
        enum CancelID { case effect }
        @Dependency(\.continuousClock) var clock
        var body: some ReducerProtocol<State, Action> {
          Reduce { state, action in
            switch action {
            case .child:
              return .none
            case .presentChild:
              state.child = Child.State()
              return .none
            case let .response(value):
              state.count = value
              return .none
            case .startButtonTapped:
              return .task {
                try await self.clock.sleep(for: .seconds(1))
                return .response(42)
              }
              .cancellable(id: CancelID.effect)
            case .stopButtonTapped:
              return .cancel(id: CancelID.effect)
            }
          }
          .presents(\.$child, action: /Action.child) {
            Child()
          }
        }
      }

      let clock = TestClock()
      let store = TestStore(
        initialState: Parent.State(),
        reducer: Parent()
      ) {
        $0.continuousClock = clock
      }
      await store.send(.presentChild) {
        $0.child = Child.State()
      }
      await store.send(.startButtonTapped)
      await store.send(.child(.presented(.stopButtonTapped)))
      await clock.advance(by: .seconds(1))
      await store.receive(.response(42)) {
        $0.count = 42
      }
      await store.send(.stopButtonTapped)
      await store.send(.child(.dismiss)) {
        $0.child = nil
      }
    }

    @available(iOS 16, macOS 13, tvOS 16, watchOS 9, *)
    func testNavigation_cancelID_parentDismissGrandchild() async {
      struct Grandchild: ReducerProtocol {
        struct State: Equatable {}
        enum Action: Equatable {
          case response(Int)
          case startButtonTapped
        }
        enum CancelID { case effect }
        @Dependency(\.continuousClock) var clock
        func reduce(into state: inout State, action: Action) -> EffectTask<Action> {
          switch action {
          case .response:
            return .none
          case .startButtonTapped:
            return .task {
              try await clock.sleep(for: .seconds(0))
              return .response(42)
            }
            .cancellable(id: CancelID.effect)
          }
        }
      }

      struct Child: ReducerProtocol {
        struct State: Equatable {
          @PresentationState var grandchild: Grandchild.State?
        }
        enum Action: Equatable {
          case grandchild(PresentationAction<Grandchild.Action>)
          case presentGrandchild
        }
        var body: some ReducerProtocolOf<Self> {
          Reduce { state, action in
            switch action {
            case .grandchild:
              return .none
            case .presentGrandchild:
              state.grandchild = Grandchild.State()
              return .none
            }
          }
          .presents(\.$grandchild, action: /Action.grandchild) {
            Grandchild()
          }
        }
      }

      struct Parent: ReducerProtocol {
        struct State: Equatable {
          @PresentationState var child: Child.State?
        }
        enum Action: Equatable {
          case child(PresentationAction<Child.Action>)
          case dismissGrandchild
          case presentChild
        }
        var body: some ReducerProtocol<State, Action> {
          Reduce { state, action in
            switch action {
            case .child:
              return .none
            case .dismissGrandchild:
              return .send(.child(.presented(.grandchild(.dismiss))))
            case .presentChild:
              state.child = Child.State()
              return .none
            }
          }
          .presents(\.$child, action: /Action.child) {
            Child()
          }
        }
      }

      await _withMainSerialExecutor {
        let clock = TestClock()
        let store = TestStore(
          initialState: Parent.State(),
          reducer: Parent()
        ) {
          $0.continuousClock = clock
        }
        await store.send(.presentChild) {
          $0.child = Child.State()
        }
        await store.send(.child(.presented(.presentGrandchild))) {
          $0.child?.grandchild = Grandchild.State()
        }

        await store.send(.child(.presented(.grandchild(.presented(.startButtonTapped)))))
        await clock.advance()
        await store.receive(.child(.presented(.grandchild(.presented(.response(42))))))

        await store.send(.child(.presented(.grandchild(.presented(.startButtonTapped)))))
        await store.send(.dismissGrandchild)
        await store.receive(.child(.presented(.grandchild(.dismiss)))) {
          $0.child?.grandchild = nil
        }
        await store.send(.child(.dismiss)) {
          $0.child = nil
        }
      }
    }

    func testRuntimeWarn_NilChild_SendDismissAction() async {
      struct Child: ReducerProtocol {
        struct State: Equatable {}
        enum Action: Equatable {}
        func reduce(into state: inout State, action: Action) -> EffectTask<Action> {
        }
      }

      struct Parent: ReducerProtocol {
        struct State: Equatable {
          @PresentationState var child: Child.State?
        }
        enum Action: Equatable {
          case child(PresentationAction<Child.Action>)
        }
        var body: some ReducerProtocol<State, Action> {
          Reduce { state, action in
            .none
          }
          .presents(\.$child, action: /Action.child) {
            Child()
          }
        }
      }

      let store = TestStore(
        initialState: Parent.State(),
        reducer: Parent()
      )

      XCTExpectFailure {
        $0.compactDescription == """
          A "presents" at \
          "ComposableArchitectureTests/PresentationReducerTests.swift:\(#line - 14)" received a \
          presentation action when destination state was absent. …

            Action:
              PresentationReducerTests.Parent.Action.child(.dismiss)

          This is generally considered an application logic error, and can happen for a few reasons:

          • A parent reducer set destination state to "nil" before this reducer ran. This reducer \
          must run before any other reducer sets destination state to "nil". This ensures that \
          destination reducers can handle their actions while their state is still present.

          • This action was sent to the store while destination state was "nil". Make sure that \
          actions for this reducer can only be sent from a view store when state is present, or \
          from effects that start from this reducer. In SwiftUI applications, use a Composable \
          Architecture view modifier like "sheet(store:…)".
          """
      }

      await store.send(.child(.dismiss))
    }

    func testRuntimeWarn_NilChild_SendChildAction() async {
      struct Child: ReducerProtocol {
        struct State: Equatable {}
        enum Action: Equatable {
          case tap
        }
        func reduce(into state: inout State, action: Action) -> EffectTask<Action> {
          .none
        }
      }

      struct Parent: ReducerProtocol {
        struct State: Equatable {
          @PresentationState var child: Child.State?
        }
        enum Action: Equatable {
          case child(PresentationAction<Child.Action>)
        }
        var body: some ReducerProtocol<State, Action> {
          Reduce { state, action in
            .none
          }
          .presents(\.$child, action: /Action.child) {
            Child()
          }
        }
      }

      let store = TestStore(
        initialState: Parent.State(),
        reducer: Parent()
      )

      XCTExpectFailure {
        $0.compactDescription == """
          A "presents" at \
          "ComposableArchitectureTests/PresentationReducerTests.swift:\(#line - 14)" received a \
          presentation action when destination state was absent. …

            Action:
              PresentationReducerTests.Parent.Action.child(.presented(.tap))

          This is generally considered an application logic error, and can happen for a few reasons:

          • A parent reducer set destination state to "nil" before this reducer ran. This reducer \
          must run before any other reducer sets destination state to "nil". This ensures that \
          destination reducers can handle their actions while their state is still present.

          • This action was sent to the store while destination state was "nil". Make sure that \
          actions for this reducer can only be sent from a view store when state is present, or \
          from effects that start from this reducer. In SwiftUI applications, use a Composable \
          Architecture view modifier like "sheet(store:…)".
          """
      }

      await store.send(.child(.presented(.tap)))
    }

    func testRehydrateSameChild_SendDismissAction() async {
      struct Child: ReducerProtocol {
        struct State: Equatable {}
        enum Action: Equatable {}
        func reduce(into state: inout State, action: Action) -> EffectTask<Action> {
        }
      }

      struct Parent: ReducerProtocol {
        struct State: Equatable {
          @PresentationState var child: Child.State?
        }
        enum Action: Equatable {
          case child(PresentationAction<Child.Action>)
        }
        var body: some ReducerProtocol<State, Action> {
          Reduce { state, action in
            switch action {
            case .child(.dismiss):
              state.child = Child.State()
              return .none
            default:
              return .none
            }
          }
          .presents(\.$child, action: /Action.child) {
            Child()
          }
        }
      }

      let store = TestStore(
        initialState: Parent.State(child: Child.State()),
        reducer: Parent()
      )

      await store.send(.child(.dismiss)) {
        $0.child = nil
      }
    }

    func testRehydrateDifferentChild_SendDismissAction() async {
      struct Child: ReducerProtocol {
        struct State: Equatable, Identifiable {
          let id: UUID
        }
        enum Action: Equatable {}
        func reduce(into state: inout State, action: Action) -> EffectTask<Action> {
        }
      }

      struct Parent: ReducerProtocol {
        struct State: Equatable {
          @PresentationState var child: Child.State?
        }
        enum Action: Equatable {
          case child(PresentationAction<Child.Action>)
        }
        @Dependency(\.uuid) var uuid
        var body: some ReducerProtocol<State, Action> {
          Reduce { state, action in
            switch action {
            case .child(.dismiss):
              if state.child?.id == UUID(uuidString: "DEADBEEF-DEAD-BEEF-DEAD-BEEFDEADBEEF") {
                state.child = Child.State(id: self.uuid())
              }
              return .none
            default:
              return .none
            }
          }
          .presents(\.$child, action: /Action.child) {
            Child()
          }
        }
      }

      let store = TestStore(
        initialState: Parent.State(
          child: Child.State(id: UUID(uuidString: "DEADBEEF-DEAD-BEEF-DEAD-BEEFDEADBEEF")!)
        ),
        reducer: Parent()
      ) {
        $0.uuid = .incrementing
      }

      await store.send(.child(.dismiss)) {
        $0.child = Child.State(id: UUID(uuidString: "00000000-0000-0000-0000-000000000000")!)
      }
      await store.send(.child(.dismiss)) {
        $0.child = nil
      }
    }
  }
#endif