/// Treat user search text as a literal substring, never SQL wildcards.
String searchSqlLikePattern(String keyword) =>
    '%${keyword.toLowerCase().replaceAll('!', '!!').replaceAll('%', '!%').replaceAll('_', '!_')}%';
