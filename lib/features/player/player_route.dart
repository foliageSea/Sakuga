/// Location of the full-screen player for [itemId].
///
/// The item is a query parameter so `/player` stays a single route: a nested
/// `/player/:itemId` route would build an empty player page underneath the one
/// that carries the item.
String playerLocation(String itemId) =>
    Uri(path: '/player', queryParameters: {'item': itemId}).toString();
