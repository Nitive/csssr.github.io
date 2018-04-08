# Новый контекст React в деталях

### Что такое контекст

В React компонентах, помимо `props`, которые могут быть доступны только у первого потомка от родителя, есть контекст, который доступен у всех потомков родителя (объявившего контекст). Это означает, что как бы глубоко компонент ни находился в дереве компонентов, он имеет доступ к контексту, который мог быть создан на сколь угодно много ветвлений дерева выше (ближе к корню). При этом если контекст обновляется — это также вызывает обновление всех подписанных (использующих контекст) потомков. На основе этого API работают все популярные библиотеки, которым необходимо иметь доступ к общим данным из любой глубины приложения: react-redux, react-mobx, react-router, styled-components (ThemeProvider).

### Проблемы старого контекста

В [старой версии](https://reactjs.org/docs/legacy-context.html), если на определённый контекст подписан и родитель — **componentA**, и его непосредственный потомок — **componentB**, то при обновлении контекста нужно произвести обновление их обоих. Из-за этого **componentA** обновится 1 раз, а **componentB** два раза: сначала из-за обновления родителя **componentA**, а потом из-за обновления самого контекста (т.к. компонент на него подписан). Соответственно, количество обновлений подписанного компонента === количеству его подписанных родителей + 1 (собственная подписка компонента). Конечно, это неэффективно и трудозатратно с точки зрения производительности.

Существуют техники и алгоритмы обхода подписчиков таким образом, чтобы минимизировать (или полностью исключить) дублирование обновления глубоколежащих подписчиков, но их реализация может быть трудоёмкой. Подробнее об этом [рассказывал](https://youtu.be/TfxfRkNCnmk) автор библиотеки `mobx`. Также можно посмотреть примеры реализации в `react-redux` [тут](https://github.com/reactjs/react-redux/blob/master/src/utils/Subscription.js) и [тут](https://github.com/reactjs/react-redux/blob/master/src/components/connectAdvanced.js#L194). Это является проблемой при разработке библиотеки, имеющей глобальное динамическое состояние, автор должен тратить лишние силы и думать об обновлении подписчиков (реализовывать свой механизм «правильного» обхода поверх механизма контекста). Хотя этим, казалось бы, должен заниматься React.

### Новое API `React.createContext`

Многие восприняли новый контекст ([`React.createContext`](https://reactjs.org/docs/context.html) — [на русском](https://habrahabr.ru/company/ruvds/blog/348862/)) как замену `redux` (или любого другого менеджера состояний), но это как сравнивать тёплое и мягкое. В действительности основная цель обновления контекста — взять на себя задачу по эффективному обновлению подписчиков ([подробности](https://twitter.com/dan_abramov/status/976486152197812229) от Дэна Абрамова), чтобы авторы библиотек могли сконцентрироваться на целевом функционале разрабатываемого пакета. Также обновлённый контекст предоставляет более удобный интерфейс для его использования.

При этом можно отметить, что `redux` имеет минимальное API для работы с состоянием: подписка и обновление, которое может быть заменено на использование `state` (и `setState`) из обычного `React.Component`. Поэтому правильнее сказать, что новый контекст в каких-то задачах можно использовать вместо `redux`, подразумевая, что вместо него будет использоваться состояние и обновление `React.Component`, а вместо `react-redux` — `React.createContext`. При этом "in box" замены `middleware` из `redux` с использованием контекста нет, в этом случае можно воспользоваться [сторонними библиотеками](https://github.com/didierfranc/react-waterfall#redux-devtools).

#### render-prop

Как можно заметить, новое API `React.createContext` использует технику render-prop для связи с подписанными компонентами. Подробности реализации и примеры использования есть в [официальной документации](https://reactjs.org/docs/render-props.html), мне же хотелось бы прояснить ключевые плюсы и минусы этого подхода:

* (**+**) Исключение коллизии имён при использовании нескольких подписок (`Consumer`). Классические HOC осуществляют слияние `props`, и если у нас есть несколько HOC подряд, и у каких-то из них совпадают названия передаваемых параметров, то они будут перезатираться, и в конечном объекте `props`, который дойдёт до компонента, будет аргумент из последнего HOC. С render-prop эта проблема исчезает, т.к. с каждым передаваемом параметре подписки нужно работать индивидуально в передаваемой функции.
* (**-**) "Сallback hell" и пересоздание функций или необходимость выносить части render, т.е. отрисовку отображения, в отдельные методы (что нарушает консистентность шаблона). Подробности — в [официальной документации](https://reactjs.org/docs/render-props.html#be-careful-when-using-render-props-with-reactpurecomponent).

Если вам не нравится подход render-prop, и вы хотите использовать «старые добрые» HOC, вот простой пример, как это можно сделать с мемоизацией:

```javascript
export const connect = selector => target => ({ children, ...props }) => {
  let updateFromParent = true;
  let cachedState = null;
  let cachedComponent = null;
  return (
    <Consumer>
      {context => {
        const state = selector(context, props);
        if (!updateFromParent && (state === cachedState || shallowCompare(state, cachedState))) {
          updateFromParent = false;
          return cachedComponent;
        } else {
          updateFromParent = false;
          cachedState = state;
          return (cachedComponent = React.createElement(target, { ...props, ...state }, children));
        }
      }}
    </Consumer>
  );
};

// example
// ComponentList.js
export const ComponentList = connect(context => ({ list: context.list }))(ComponentList_raw);
```

### `unstable_observedBits`

> информация взята из [исходников](https://github.com/facebook/react/blob/4ccf58a94dce323718540b8185a32070ded6094b/packages/react/src/ReactContext.js#L18) и [тестов](https://github.com/facebook/react/blob/4ccf58a94dce323718540b8185a32070ded6094b/packages/react-reconciler/src/__tests__/ReactNewContext-test.internal.js#L498-L526) React, а также из [этой статьи](https://medium.com/@koba04/a-secret-parts-of-react-new-context-api-e9506a4578aa)

Публично об этом ещё не заявляли, и в официальной документации информации об этой части API нет, но, помимо вышесказанного, у `React.createContext` есть второй аргумент, принимающий функцию, а у `Consumer` есть параметр `unstable_observedBits`, принимающий битовую маску сопоставления. Это аналогично `shouldComponentUpdate` у `React.Component`. Разберём подробнее.

#### Битовые маски
[Битовые маски](https://ru.wikipedia.org/wiki/Битовая_маска) применяются очень давно, в частности, для сопоставления прав доступа в Linux. Суть заключается в том, что каждый бит в своей очерёдности на битовой маске отвечает за `true` или `false` по отношению к определённому правилу. Удобность работы с побитовыми масками заключается в том, что для обновления значения достаточно осуществить побитовую операцию оригинальной маски с маской правила, в которой для установки значения в `true` необходимо применить "ИЛИ" — `|`, где управляющий бит === `1`, а остальные — `0`, а для установки значения в `false` необходимо применить "И" — `&`, где управляющий бит === `0`, а остальные — `1`. Это может поначалу звучать сложно, но на практике это простой, наглядный, а главное, самый быстрый способ записи и управления диапазоном значений `true` \ `false`.

#### Использование
Битовая маска в описании и примерах ниже используется для отслеживания изменений в `state`. Каждому значению `state` должен соответствовать бит в битовой маске.

Второй аргумент `React.createContext` принимает функцию, которая на вход получает предыдущее и обновлённое состояние, а на выходе должна вернуть обновлённую битовую маску. В свою очередь `Consumer` принимает в `unstable_observedBits` битовую маску, которая содержит биты положительных значений, отвечающих за отслеживаемые позиции `state`. При поступлении изменений `Consumer` сначала [сравнивает](https://github.com/facebook/react/blob/4ccf58a94dce323718540b8185a32070ded6094b/packages/react-reconciler/src/ReactFiberBeginWork.js#L988) обновлённую битовую маску с `unstable_observedBits`, и если их побитовое сложение возвращает не `0`, то render-prop будет вызван, иначе — нет. Если второй аргумент `React.createContext` и `unstable_observedBits` у `Consumer` не заданы — вызов render-prop будет происходить на любое изменение контекста.

#### Пример

```javascript
const store = {
  observedBits: {
    foo: 0b01,
    bar: 0b10
  },
  state: {
    foo: 1,
    bar: 1,
  },
  update(cb) {
    this.state = cb(this.state);
  }
};

const StoreContext = React.createContext(
  store.state,
  (prev, next) => {
    let result = 0;
    // поменялся `foo`
    if (prev.foo !== next.foo) {
      result |= store.observedBits.foo;
    }
    // поменялся `bar`
    if (prev.bar !== next.bar) {
      result |= store.observedBits.bar;
    }
    return result;
  }
);

const Foo = () => (
  <StoreContext.Consumer unstable_observedBits={store.observedBits.foo}>
    {({foo, update}) => ( // если поменяется `bar`, этот код не выполнится
      <button
        onClick={() => update((state) => ({...state, foo: state.foo + 1}))}
      >
        increment "foo = {foo}"
      </button>
    )}
  </StoreContext.Consumer>
);
```

Как ясно из названия параметров, данное API ещё не стабильно и не стоит использовать его в проде.

### `create-subscription`

Также в [исходных кодах](https://github.com/facebook/react/tree/master/packages/create-subscription) React появился пакет [`create-subscription`](https://reactjs.org/blog/2018/03/27/update-on-async-rendering.html#adding-event-listeners-or-subscriptions). Раньше для того, чтобы подписаться и как-то реагировать на внешние изменения и производить ререндер компонентов, необходимо было делать обёртку в виде класса `React.Component`, в которой при поступлении уведомлений вызывать `setState` — т.е. дублировать данные из пришедшего уведомления — или [`forceUpdate`](https://reactjs.org/docs/react-component.html#forceupdate) — чего лучше избегать. Для упрощения подписки теперь можно использовать более прозрачное API `createSubscription` из пакета `create-subscription` официального репозитория React.

### Резюмируя
Обновление React 16.3 принесло множество интересных изменений и, безусловно, облегчит и повысит качество использования React и разработку вспомогательных библиотек для него. Все вышеописанные технологии можно посмотреть в интерактивной демонстрации:

[![demo](https://codesandbox.io/static/img/play-codesandbox.svg)](https://codesandbox.io/s/2onvlynj1r)
