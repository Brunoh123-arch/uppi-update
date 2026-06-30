const fs = require('fs');
const path = require('path');

const url = process.env.SUPABASE_MIGRATION_URL || "https://kqfmahrxjuqlvxngeurj.supabase.co/functions/v1/run-migrations";
const token = `Bearer ${process.env.SUPABASE_SERVICE_KEY || ""}`;

if (!process.env.SUPABASE_SERVICE_KEY) {
  console.error("❌ ERRO: Defina a variável de ambiente SUPABASE_SERVICE_KEY antes de executar.");
  console.error("   Exemplo: set SUPABASE_SERVICE_KEY=SuaChaveAqui && node scripts/backup_data.js");
  process.exit(1);
}

const tables = [
  'profiles',
  'services',
  'app_settings',
  'admins',
  'coupons',
  'driver_locations',
  'rides',
  'ride_offers',
  'wallet_transactions',
  'payout_requests',
  'coupon_usages'
];

async function runQuery(query) {
  const response = await fetch(url, {
    method: "POST",
    headers: {
      "Authorization": token,
      "Content-Type": "application/json"
    },
    body: JSON.stringify({ query })
  });
  const result = await response.json();
  if (!result.success) {
    throw new Error(result.error);
  }
  return result.data;
}

function escapeValue(val) {
  if (val === null || val === undefined) return 'NULL';
  if (typeof val === 'boolean') return val ? 'true' : 'false';
  if (typeof val === 'number') return val.toString();
  if (typeof val === 'object') {
    // Para campos JSON/JSONB
    return `'${JSON.stringify(val).replace(/'/g, "''")}'`;
  }
  // Trata string e data
  return `'${val.toString().replace(/'/g, "''")}'`;
}

async function backup() {
  const backupPath = path.join(__dirname, '..', 'backup_dados.sql');
  const stream = fs.createWriteStream(backupPath, { encoding: 'utf8' });
  
  stream.write(`-- ==========================================================\n`);
  stream.write(`-- BACKUP DE DADOS DO BANCO UPPI (SUPABASE)\n`);
  stream.write(`-- Gerado em: ${new Date().toISOString()}\n`);
  stream.write(`-- ==========================================================\n\n`);
  stream.write(`BEGIN;\n\n`);
  
  // Desativar triggers temporariamente para evitar falhas de RLS/Integridade durante o restore
  stream.write(`SET session_replication_role = 'replica';\n\n`);
  
  for (const table of tables) {
    console.log(`Fazendo backup da tabela: ${table}...`);
    try {
      const rows = await runQuery(`SELECT * FROM public.${table}`);
      if (rows.length === 0) {
        stream.write(`-- Tabela public.${table} está vazia\n\n`);
        continue;
      }
      
      stream.write(`-- Dados da tabela public.${table} (${rows.length} linhas)\n`);
      stream.write(`TRUNCATE TABLE public.${table} CASCADE;\n`);
      
      const columns = Object.keys(rows[0]);
      const columnsStr = columns.map(c => `"${c}"`).join(', ');
      
      for (const row of rows) {
        const valuesStr = columns.map(col => escapeValue(row[col])).join(', ');
        stream.write(`INSERT INTO public.${table} (${columnsStr}) VALUES (${valuesStr});\n`);
      }
      stream.write(`\n`);
    } catch (err) {
      console.error(`Erro ao fazer backup da tabela ${table}:`, err.message);
      stream.write(`-- ERRO NO BACKUP DA TABELA ${table}: ${err.message}\n\n`);
    }
  }
  
  // Reativar triggers
  stream.write(`SET session_replication_role = 'origin';\n\n`);
  stream.write(`COMMIT;\n`);
  stream.end();
  
  console.log(`\nBackup concluído com sucesso em: ${backupPath}`);
}

backup();
