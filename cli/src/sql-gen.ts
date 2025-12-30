

// Types matching Zig output
interface DiffEntry {
  create_table?: CreateTable;
  drop_table?: string;
  alter_table?: AlterTable;
}

interface CreateTable {
  table: string;
  schema?: string | null;
  columns: { items?: Column[]; capacity?: number } | Column[];
  primary_key_columns: { items?: string[] } | string[];
}

interface AlterTable {
  name: string;
  changes: { items?: TableChange[]; capacity?: number } | TableChange[];
}

type TableChange = 
  | { add_column: Column }
  | { drop_column: string }
  | { modify_column: ColumnModification };

interface Column {
  name: string;
  data_type: string;
  nullable: boolean;
  primary_key: boolean;
  unique: boolean;
  default: string | null;
  references: ForeignKey | null;
}

interface ForeignKey {
  table: string;
  column?: string;
  on_delete?: string;
}

interface ColumnModification {
  name: string;
  type_changed?: string;
  nullable_changed?: boolean;
  default_changed?: string;
}

// Helper to handle the Zig ArrayList serialization quirk (items wrapper)
function unwrap<T>(list: { items?: T[] } | T[] | undefined): T[] {
  if (!list) return [];
  if (Array.isArray(list)) return list;
  return list.items || [];
}

export function generateMigration(diff: DiffEntry[]): string {
  const statements: string[] = [];

  for (const entry of diff) {
    if (entry.create_table) {
      statements.push(generateCreateTable(entry.create_table));
    } else if (entry.drop_table) {
      statements.push(`DROP TABLE IF EXISTS "${entry.drop_table}";`);
    } else if (entry.alter_table) {
      statements.push(...generateAlterTable(entry.alter_table));
    }
  }

  return statements.join('\n\n');
}

function generateCreateTable(t: CreateTable): string {
  const cols = unwrap(t.columns).map(col => {
    let def = `  "${col.name}" ${col.data_type}`;
    if (!col.nullable) def += " NOT NULL";
    if (col.default) def += ` DEFAULT ${col.default}`;
    if (col.primary_key) def += " PRIMARY KEY";
    if (col.unique) def += " UNIQUE";
    if (col.references) {
      def += ` REFERENCES "${col.references.table}"`;
      if (col.references.column) def += `("${col.references.column}")`;
      if (col.references.on_delete) def += ` ON DELETE ${col.references.on_delete}`;
    }
    return def;
  });

  const pks = unwrap(t.primary_key_columns);
  if (pks.length > 0) {
    cols.push(`  PRIMARY KEY (${pks.map(k => `"${k}"`).join(', ')})`);
  }

  return `CREATE TABLE "${t.table}" (\n${cols.join(',\n')}\n);`;
}

function generateAlterTable(a: AlterTable): string[] {
  const stmts: string[] = [];
  const changes = unwrap(a.changes);

  for (const change of changes) {
    if ('add_column' in change) {
      const col = change.add_column;
      let def = `ADD COLUMN "${col.name}" ${col.data_type}`;
      if (!col.nullable) def += " NOT NULL";
      if (col.default) def += ` DEFAULT ${col.default}`;
      if (col.references) {
          def += ` REFERENCES "${col.references.table}"`;
          if (col.references.column) def += `("${col.references.column}")`;
      }
      stmts.push(`ALTER TABLE "${a.name}" ${def};`);
    } 
    else if ('drop_column' in change) {
      // SAFETY: Generate a warning for data loss
      stmts.push(`-- SAFEGUARD: The following line drops data. Uncomment to execute.`);
      stmts.push(`-- ALTER TABLE "${a.name}" DROP COLUMN "${change.drop_column}";`);
    }
    else if ('modify_column' in change) {
      const mod = change.modify_column;
      if (mod.type_changed) {
        stmts.push(`ALTER TABLE "${a.name}" ALTER COLUMN "${mod.name}" TYPE ${mod.type_changed};`);
      }
      if (mod.nullable_changed !== undefined) {
        const action = mod.nullable_changed ? "DROP NOT NULL" : "SET NOT NULL";
        stmts.push(`ALTER TABLE "${a.name}" ALTER COLUMN "${mod.name}" ${action};`);
      }
      if (mod.default_changed !== undefined) {
        if (mod.default_changed === null) {
             stmts.push(`ALTER TABLE "${a.name}" ALTER COLUMN "${mod.name}" DROP DEFAULT;`);
        } else {
             stmts.push(`ALTER TABLE "${a.name}" ALTER COLUMN "${mod.name}" SET DEFAULT ${mod.default_changed};`);
        }
      }
    }
  }

  return stmts;
}
