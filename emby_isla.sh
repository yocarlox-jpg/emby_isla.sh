  echo -e "${YELLOW}Rutas /mnt de Emby que NO coinciden con mounts esperados:${NC}"
  sqlite3 "$DB" "
    WITH roots AS (
      SELECT DISTINCT
        substr(
          Path,
          1,
          CASE
            WHEN instr(substr(Path,6),'/') = 0 THEN length(Path)
            ELSE instr(substr(Path,6),'/') + 4
          END
        ) AS RootPath
      FROM MediaItems
      WHERE Path LIKE '/mnt/%'

      UNION

      SELECT DISTINCT
        substr(
          Path,
          1,
          CASE
            WHEN instr(substr(Path,6),'/') = 0 THEN length(Path)
            ELSE instr(substr(Path,6),'/') + 4
          END
        ) AS RootPath
      FROM MediaStreams2
      WHERE Path LIKE '/mnt/%'
    )
    SELECT RootPath
    FROM roots
    WHERE RootPath NOT IN ($SQL_MOUNTS)
    ORDER BY RootPath;
  " | sed '/^$/d'
