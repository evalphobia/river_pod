import 'package:mockito/mockito.dart';
import 'package:riverpod/riverpod.dart';
import 'package:riverpod/src/internals.dart';
import 'package:state_notifier/state_notifier.dart';
import 'package:test/test.dart';

class Counter extends StateNotifier<int> {
  Counter([int initialValue = 0]) : super(initialValue);

  @override
  int get state => super.state;
  @override
  set state(int value) => super.state = value;

  void increment() => state++;
}

void main() {
  test(
      'after a computed is destroyed, Owner.traverse states does not visit the state',
      () async {
    final notifier = Counter(1);
    final provider = StateNotifierProvider((ref) => notifier);
    final computed = Computed((read) => read(provider.state) * 2);
    final listener = Listener<int>();
    final owner = ProviderStateOwner();

    computed.watchOwner(owner, listener)();

    verify(listener(2)).called(1);
    verifyNoMoreInteractions(listener);

    await Future<void>.value();

    verifyNoMoreInteractions(listener);
    expect(
      owner.debugProviderValues.keys,
      unorderedMatches(<Object>[provider, provider.state]),
    );

    notifier.state++;

    await Future<void>.value();
    verifyNoMoreInteractions(listener);

    computed.watchOwner(owner, listener);

    verify(listener(4)).called(1);
    verifyNoMoreInteractions(listener);
    expect(
      owner.debugProviderValues.keys,
      unorderedMatches(<Object>[provider, provider.state, computed]),
    );
  });
  test(
      'Computed removing one of multiple listeners on a provider still listen to the provider',
      () {
    final stateProvider = StateProvider((ref) => 0, name: 'state');
    final notifier0 = Counter();
    final notifier1 = Counter(42);
    final provider0 = StateNotifierProvider((_) => notifier0, name: '0');
    final provider1 = StateNotifierProvider((_) => notifier1, name: '1');
    var buildCount = 0;
    final computed = Computed((read) {
      buildCount++;

      final state = read(stateProvider).state;
      final value = state == 0 ? read(provider0.state) : read(provider1.state);

      return '${read(provider0.state)} $value';
    });
    final listener = Listener<String>();
    final owner = ProviderStateOwner();

    provider0.state.readOwner(owner);
    provider1.state.readOwner(owner);
    final familyState0 = owner.debugProviderStates.firstWhere((p) {
      return p.provider == provider0.state;
    });
    final familyState1 = owner.debugProviderStates.firstWhere((p) {
      return p.provider == provider1.state;
    });

    computed.watchOwner(owner, listener);

    expect(buildCount, 1);
    expect(familyState0.$hasListeners, true);
    expect(familyState1.$hasListeners, false);
    verify(listener('0 0')).called(1);
    verifyNoMoreInteractions(listener);

    notifier0.increment();

    expect(buildCount, 2);
    verify(listener('1 1')).called(1);
    verifyNoMoreInteractions(listener);

    notifier1.increment();

    expect(buildCount, 2);
    verifyNoMoreInteractions(listener);

    // changing the provider that computed is subscribed to
    stateProvider.readOwner(owner).state = 1;

    expect(buildCount, 3);
    verify(listener('1 43')).called(1);
    verifyNoMoreInteractions(listener);
    expect(familyState1.$hasListeners, true);
    expect(familyState0.$hasListeners, true);

    notifier1.increment();

    expect(buildCount, 4);
    verify(listener('1 44')).called(1);
    verifyNoMoreInteractions(listener);

    notifier0.increment();

    expect(buildCount, 5);
    verify(listener('2 44')).called(1);
    verifyNoMoreInteractions(listener);
  });
  test('Stops listening to a provider when recomputed but no longer using it',
      () {
    final stateProvider = StateProvider((ref) => 0, name: 'state');
    final notifier0 = Counter();
    final notifier1 = Counter(42);
    final provider0 = StateNotifierProvider((_) => notifier0, name: '0');
    final provider1 = StateNotifierProvider((_) => notifier1, name: '1');
    var buildCount = 0;
    final computed = Computed((read) {
      buildCount++;
      final state = read(stateProvider).state;
      return state == 0 ? read(provider0.state) : read(provider1.state);
    });
    final listener = Listener<int>();
    final owner = ProviderStateOwner();

    provider0.state.readOwner(owner);
    provider1.state.readOwner(owner);
    final familyState0 = owner.debugProviderStates.firstWhere((p) {
      return p.provider == provider0.state;
    });
    final familyState1 = owner.debugProviderStates.firstWhere((p) {
      return p.provider == provider1.state;
    });

    computed.watchOwner(owner, listener);

    expect(buildCount, 1);
    expect(familyState0.$hasListeners, true);
    expect(familyState1.$hasListeners, false);
    verify(listener(0)).called(1);
    verifyNoMoreInteractions(listener);

    notifier0.increment();

    expect(buildCount, 2);
    verify(listener(1)).called(1);
    verifyNoMoreInteractions(listener);

    notifier1.increment();

    expect(buildCount, 2);
    verifyNoMoreInteractions(listener);

    // changing the provider that computed is subscribed to
    stateProvider.readOwner(owner).state = 1;

    expect(buildCount, 3);
    verify(listener(43)).called(1);
    verifyNoMoreInteractions(listener);
    expect(familyState1.$hasListeners, true);
    expect(familyState0.$hasListeners, false);

    notifier1.increment();

    expect(buildCount, 4);
    verify(listener(44)).called(1);
    verifyNoMoreInteractions(listener);

    notifier0.increment();

    expect(buildCount, 4);
    verifyNoMoreInteractions(listener);
  });
  test('Computed.family', () {
    final computed =
        Computed.family<String, SetStateProvider<int>>((read, provider) {
      return read(provider).toString();
    });
    final notifier = Counter();
    final provider = StateNotifierProvider((_) => notifier);
    final owner = ProviderStateOwner();
    final listener = Listener<String>();

    computed(provider.state).watchOwner(owner, listener);

    verify(listener('0')).called(1);
    verifyNoMoreInteractions(listener);

    notifier.state = 42;

    verify(listener('42')).called(1);
    verifyNoMoreInteractions(listener);
  });
  test('auto dispose Computed when no longer used', () async {
    final owner = ProviderStateOwner();
    final onDispose = OnDisposeMock();
    final provider = Provider.autoDispose((ref) {
      ref.onDispose(onDispose);
      return 42;
    });
    final computed = Computed((read) => read(provider));

    final removeListener = computed.watchOwner(owner, (value) {});

    verifyNoMoreInteractions(onDispose);
    removeListener();
    verifyNoMoreInteractions(onDispose);

    await Future<void>.value();

    verify(onDispose());
    verifyNoMoreInteractions(onDispose);
  });
  test(
      'mutliple read, when one of them forces re-evaluate, all dependencies are still flushed',
      () {
    final owner = ProviderStateOwner();
    final notifier = Notifier(0);
    final provider = StateNotifierProvider((_) => notifier);
    var callCount = 0;
    final computed = Computed((read) {
      callCount++;
      return read(provider.state);
    });

    final tested = Computed((read) {
      final first = read(provider.state);
      final second = read(computed);
      return '$first $second';
    });
    final listener = Listener<String>();

    final sub = tested.addLazyListener(
      owner,
      mayHaveChanged: () {},
      onChange: listener,
    );

    verify(listener('0 0')).called(1);
    verifyNoMoreInteractions(listener);
    expect(callCount, 1);

    notifier.setState(1);
    sub.flush();

    verify(listener('1 1')).called(1);
    verifyNoMoreInteractions(listener);
    expect(callCount, 2);
  });
  test(
      'computed on computed, the first aborts rebuild, the second should no longer be dirty after a flush',
      () {
    final owner = ProviderStateOwner();
    final notifier = Notifier(0);
    final provider = StateNotifierProvider((_) => notifier);
    final first = Computed((read) {
      // force re-evauating the computed
      read(provider.state);
      return 0;
    });
    final second = Computed((read) {
      return read(first);
    });
    final mayHaveChanged = MockMarkMayHaveChanged();
    final listener = Listener<int>();

    final sub = second.addLazyListener(
      owner,
      mayHaveChanged: mayHaveChanged,
      onChange: listener,
    );

    verify(listener(0)).called(1);
    verifyNoMoreInteractions(listener);
    verifyNoMoreInteractions(mayHaveChanged);

    notifier.setState(42);

    verify(mayHaveChanged()).called(1);
    verifyNoMoreInteractions(listener);
    verifyNoMoreInteractions(mayHaveChanged);

    sub.flush();

    verifyNoMoreInteractions(listener);
    verifyNoMoreInteractions(mayHaveChanged);

    final firstState = owner //
        .debugProviderStates
        .firstWhere((s) => s.provider == first);
    final secondState = owner //
        .debugProviderStates
        .firstWhere((s) => s.provider == second);

    expect(firstState.dirty, false);
    expect(secondState.dirty, false);
  });
  test(
      'Computed are stored on the deeper ProviderStateOwner and cannot be overriden (insert in parent owner first then child owner)',
      () {
    final root = ProviderStateOwner();
    final owner = ProviderStateOwner(parent: root);
    var callCount = 0;
    final computed = Computed((_) => callCount++);
    final rootListener = Listener<int>();
    final ownerListener = Listener<int>();

    computed.watchOwner(root, rootListener);

    expect(callCount, 1);
    verify(rootListener(0)).called(1);
    verifyNoMoreInteractions(rootListener);

    computed.watchOwner(owner, ownerListener);

    expect(callCount, 2);
    verify(ownerListener(1)).called(1);
    verifyNoMoreInteractions(ownerListener);

    computed.watchOwner(root, rootListener);

    expect(callCount, 2);
    verify(rootListener(0)).called(1);
    verifyNoMoreInteractions(rootListener);

    computed.watchOwner(owner, ownerListener);

    expect(callCount, 2);
    verify(ownerListener(1)).called(1);
    verifyNoMoreInteractions(ownerListener);
  });

  test('Computeds are added to the overall list of providers', () {
    final owner = ProviderStateOwner();
    final provider = Provider((_) => 42);
    final computed = Computed((read) => read(provider) * 2);
    final provider2 = Provider((ref) => ref.dependOn(computed));
    final listener = Listener<int>();

    provider2.readOwner(owner);
    computed.watchOwner(owner, listener);

    verify(listener(84)).called(1);
    verifyNoMoreInteractions(listener);

    expect(
      owner.debugProviderStates.map((e) => e.provider),
      [provider, computed, provider2],
    );
  });
  test('Computed are not overrides', () {
    expect(Computed((_) {}), isNot(isA<Override>()));
  });
  test('disposing the Computed closes subscriptions', () {
    final notifier = Notifier(0);
    final provider = StateNotifierProvider<Notifier<int>>((_) => notifier);
    final computed = Computed((read) => read(provider.state));
    final root = ProviderStateOwner();
    // no need to pass "overrides" as the computed should naturally go to the deepest owner
    final owner = ProviderStateOwner(parent: root);
    final mayHaveChanged = MockMarkMayHaveChanged();
    final listener = Listener<int>();

    final sub = computed.addLazyListener(
      owner,
      mayHaveChanged: mayHaveChanged,
      onChange: listener,
    );

    verify(listener(0)).called(1);
    verifyNoMoreInteractions(mayHaveChanged);
    verifyNoMoreInteractions(listener);

    owner.dispose();
    verifyNoMoreInteractions(mayHaveChanged);
    verifyNoMoreInteractions(listener);

    notifier.setState(42);

    verifyNoMoreInteractions(listener);
    verifyNoMoreInteractions(mayHaveChanged);

    sub.flush();

    verifyNoMoreInteractions(mayHaveChanged);
    verifyNoMoreInteractions(listener);
  });
  test('cannot call read outside of the Computed', () {
    final owner = ProviderStateOwner();
    final notifier = Notifier(0);
    final provider = StateNotifierProvider<Notifier<int>>((_) => notifier);
    var callCount = 0;
    Reader reader;
    final computed = Computed((read) {
      callCount++;
      reader = read;
      return read(provider.state);
    });
    final mayHaveChanged = MockMarkMayHaveChanged();
    final listener = Listener<int>();

    final sub = computed.addLazyListener(
      owner,
      mayHaveChanged: mayHaveChanged,
      onChange: listener,
    );

    verify(listener(0)).called(1);
    verifyNoMoreInteractions(listener);
    verifyNoMoreInteractions(mayHaveChanged);
    expect(() => reader(provider), throwsA(isA<AssertionError>()));
    expect(callCount, 1);

    notifier.setState(42);

    verify(mayHaveChanged()).called(1);
    verifyNoMoreInteractions(mayHaveChanged);
    verifyNoMoreInteractions(listener);

    sub.flush();

    verify(listener(42)).called(1);
    verifyNoMoreInteractions(mayHaveChanged);
    verifyNoMoreInteractions(listener);
    expect(() => reader(provider), throwsA(isA<AssertionError>()));
    expect(callCount, 2);
  });
  group('deeply compares collections', () {
    test('list', () {
      final owner = ProviderStateOwner();
      final notifier = Notifier(0);
      final provider = StateNotifierProvider<Notifier<int>>((_) => notifier);
      final computed = Computed((read) {
        return [read(provider.state).isNegative];
      });
      final mayHaveChanged = MockMarkMayHaveChanged();
      final listener = Listener<List<bool>>();

      final sub = computed.addLazyListener(
        owner,
        mayHaveChanged: mayHaveChanged,
        onChange: listener,
      );

      verify(listener([false])).called(1);
      verifyNoMoreInteractions(listener);
      verifyNoMoreInteractions(mayHaveChanged);

      notifier.setState(42);

      verify(mayHaveChanged()).called(1);
      verifyNoMoreInteractions(listener);
      verifyNoMoreInteractions(mayHaveChanged);

      sub.flush();

      verifyNoMoreInteractions(mayHaveChanged);
      verifyNoMoreInteractions(listener);
    });
    test('set', () {
      final owner = ProviderStateOwner();
      final notifier = Notifier(0);
      final provider = StateNotifierProvider<Notifier<int>>((_) => notifier);
      final computed = Computed((read) {
        return {read(provider.state).isNegative};
      });
      final mayHaveChanged = MockMarkMayHaveChanged();
      final listener = Listener<Set<bool>>();

      final sub = computed.addLazyListener(
        owner,
        mayHaveChanged: mayHaveChanged,
        onChange: listener,
      );

      verify(listener({false})).called(1);
      verifyNoMoreInteractions(listener);
      verifyNoMoreInteractions(mayHaveChanged);

      notifier.setState(42);

      verify(mayHaveChanged()).called(1);
      verifyNoMoreInteractions(listener);
      verifyNoMoreInteractions(mayHaveChanged);

      sub.flush();

      verifyNoMoreInteractions(mayHaveChanged);
      verifyNoMoreInteractions(listener);
    });
    test('map', () {
      final owner = ProviderStateOwner();
      final notifier = Notifier(0);
      final provider = StateNotifierProvider<Notifier<int>>((_) => notifier);
      final computed = Computed((read) {
        return {'foo': read(provider.state).isNegative};
      });
      final mayHaveChanged = MockMarkMayHaveChanged();
      final listener = Listener<Map<String, bool>>();

      final sub = computed.addLazyListener(
        owner,
        mayHaveChanged: mayHaveChanged,
        onChange: listener,
      );

      verify(listener({'foo': false})).called(1);
      verifyNoMoreInteractions(listener);
      verifyNoMoreInteractions(mayHaveChanged);

      notifier.setState(42);

      verify(mayHaveChanged()).called(1);
      verifyNoMoreInteractions(listener);
      verifyNoMoreInteractions(mayHaveChanged);

      sub.flush();

      verifyNoMoreInteractions(mayHaveChanged);
      verifyNoMoreInteractions(listener);
    });
  });
  test('the value is cached between multiple listeners', () {
    final owner = ProviderStateOwner();
    final notifier = Notifier(0);
    final provider = StateNotifierProvider<Notifier<int>>((_) => notifier);
    var callCount = 0;
    final computed = Computed((read) {
      callCount++;
      return [read(provider.state)];
    });

    List<int> first;
    final firstListener = Listener<List<int>>();
    computed.watchOwner(owner, (value) {
      first = value;
      firstListener(value);
    });
    List<int> second;
    final secondListener = Listener<List<int>>();
    computed.watchOwner(owner, (value) {
      second = value;
      secondListener(value);
    });

    expect(first, [0]);
    expect(callCount, 1);
    expect(identical(first, second), isTrue);
    verifyInOrder([
      firstListener([0]),
      secondListener([0]),
    ]);
    verifyNoMoreInteractions(firstListener);
    verifyNoMoreInteractions(secondListener);
  });
  test('Computed is not a AlwaysAliveProviderBase', () {
    final computed = Computed((read) => 0);

    expect(computed, isNot(isA<AlwaysAliveProviderBase>()));
  });
  test('Simple Computed flow', () {
    final owner = ProviderStateOwner();
    final notifier = Notifier(0);
    final provider = StateNotifierProvider<Notifier<int>>((_) => notifier);
    final mayHaveChanged = MockMarkMayHaveChanged();
    final listener = Listener<bool>();
    var callCount = 0;
    final isPositiveComputed = Computed((read) {
      callCount++;
      return !read(provider.state).isNegative;
    });

    final sub = isPositiveComputed.addLazyListener(
      owner,
      mayHaveChanged: mayHaveChanged,
      onChange: listener,
    );

    expect(notifier.hasListeners, true);
    verify(listener(true)).called(1);
    expect(callCount, 1);
    verifyNoMoreInteractions(listener);
    verifyNoMoreInteractions(mayHaveChanged);

    notifier.setState(-1);

    verify(mayHaveChanged()).called(1);
    verifyNoMoreInteractions(mayHaveChanged);
    verifyNoMoreInteractions(listener);

    sub.flush();

    expect(callCount, 2);
    verify(listener(false)).called(1);
    verifyNoMoreInteractions(mayHaveChanged);
    verifyNoMoreInteractions(listener);

    notifier.setState(-42);

    verify(mayHaveChanged()).called(1);
    verifyNoMoreInteractions(mayHaveChanged);
    verifyNoMoreInteractions(listener);

    sub.flush();

    expect(callCount, 3);
    verifyNoMoreInteractions(mayHaveChanged);
    verifyNoMoreInteractions(listener);
  });
}

class Notifier<T> extends StateNotifier<T> {
  Notifier(T state) : super(state);

  // ignore: use_setters_to_change_properties
  void setState(T value) => state = value;
}

class Listener<T> extends Mock {
  void call(T value);
}

class OnDisposeMock extends Mock {
  void call();
}

class MockMarkMayHaveChanged extends Mock {
  void call();
}
