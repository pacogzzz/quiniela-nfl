import { PGlite } from '@electric-sql/pglite';
import { pgcrypto } from '@electric-sql/pglite/contrib/pgcrypto';
import { readFileSync } from 'node:fs';
import { SHIM } from './shim.mjs';

// Ruta relativa a ESTE archivo: el arnes corre igual en cualquier maquina
// (antes era una ruta absoluta de la computadora del autor y reventaba con ENOENT).
const SQL = readFileSync(new URL('../supabase/migrations/001_init.sql', import.meta.url),'utf8');
const db = await new PGlite({ extensions: { pgcrypto } });
await db.exec(SHIM);
await db.exec(SQL);

// NO se conceden privilegios aqui a proposito.
//
// Antes este arnes hacia GRANT ALL "porque Supabase lo hace por default".
// Esa suposicion era falsa y el atajo TAPO un bug real: 001_init.sql no
// traia sus propios GRANT, la API devolvia "permission denied for table"
// en produccion, y aun asi las 33 pruebas pasaban.
//
// Ahora los permisos tienen que venir de la migracion misma. Si alguien
// agrega una tabla y olvida su GRANT, estas pruebas lo cachan.

let pass=0, fail=0;
const q   = async (s,p) => (await db.query(s,p)).rows;
const one = async (s,p) => (await q(s,p))[0];
function chk(name, got, want){
  const ok = JSON.stringify(got)===JSON.stringify(want);
  console.log(`${ok?'  ok   ':'  FALLA '}${name}${ok?'':`\n         esperado ${JSON.stringify(want)} · obtuve ${JSON.stringify(got)}`}`);
  ok?pass++:fail++;
}
// "bloqueado" = o lanza error, o (en UPDATE/DELETE con RLS) afecta 0 filas
async function blocked(name, sql, params){
  try {
    const r = await db.query(sql, params);
    const n = r.affectedRows ?? r.rows.length;
    const ok = n === 0;
    console.log(`${ok?'  ok   ':'  FALLA '}${name}${ok?' (0 filas afectadas)':`\n         PASO! afecto ${n} filas — HUECO DE SEGURIDAD`}`);
    ok?pass++:fail++;
  } catch(e){
    console.log(`  ok   ${name} (rechazado: ${e.message.split('\n')[0].slice(0,50)})`);
    pass++;
  }
}
async function allowed(name, sql, params){
  try { await db.query(sql, params); console.log(`  ok   ${name}`); pass++; }
  catch(e){ console.log(`  FALLA ${name}\n         bloqueo algo que SI debia permitir: ${e.message}`); fail++; }
}

// --- datos base como superusuario ---
const ADMIN=(await one(`insert into auth.users(email) values('admin@x.com') returning id`)).id;
const ANA  =(await one(`insert into auth.users(email) values('ana@x.com')   returning id`)).id;
const BETO =(await one(`insert into auth.users(email) values('beto@x.com')  returning id`)).id;
await q(`insert into profiles(id,nombre,email,role) values
  ($1,'Jefe','admin@x.com','admin'),($2,'Ana','ana@x.com','user'),($3,'Beto','beto@x.com','user')`,[ADMIN,ANA,BETO]);
await q(`update games set team_a='DAL',team_b='PHI' where id='W01-TNF'`);
await q(`update underdog_weeks set opt_a_game='W01-TNF',opt_a_team='DAL' where week=1`);
const folio = (await one(`insert into folios(code,fecha,puntos) values('TEST01','2026-09-14',10) returning code`)).code;

const login = async (id) => {
  await db.exec(`RESET ROLE`);
  await db.exec(`SELECT set_config('request.jwt.claim.sub','${id}',false)`);
  await db.exec(`SET ROLE authenticated`);
};

console.log('== UN JUGADOR NORMAL (Ana) NO PUEDE... ==');
await login(ANA);
await blocked('escribir pronosticos a nombre de Beto',
  `insert into picks(user_id,game_id,ganador) values($1,'W01-TNF','A')`,[BETO]);
await blocked('cargar el marcador de un partido',
  `update games set score_a=99,score_b=0 where id='W01-TNF'`);
await blocked('cambiar la configuracion de puntaje',
  `update config set valor='9999' where clave='pts_win_normal'`);
await blocked('borrar partidos',
  `delete from games where id='W01-D01'`);
await blocked('crear folios de la nada',
  `insert into folios(code,fecha,puntos) values('TRAMPA','2026-09-14',999)`);
await blocked('marcarse un folio como usado a mano',
  `update folios set usado=true, por_user_id=$1 where code=$2`,[ANA,folio]);
await blocked('leer los folios de otros',
  `select * from folios where code=$1`,[folio]);
await blocked('publicar/editar el underdog de la semana',
  `update underdog_weeks set puntos=9999 where week=1`);
await blocked('ascenderse a admin',
  `update profiles set role='admin' where id=$1`,[ANA]);
await blocked('escribir en el historial',
  `insert into historial(titulo) values('hackeado')`);
await blocked('inventarse un corte de semana',
  `insert into week_snapshots(week,user_id,posicion,total) values(1,$1,1,99999)`,[ANA]);
await blocked('regalarse puntos con un bono',
  `insert into bonos(user_id,motivo,puntos) values($1,'trampa',9999)`,[ANA]);

console.log('\n== ...PERO SI PUEDE HACER LO SUYO ==');
await allowed('guardar su propio pronostico',
  `insert into picks(user_id,game_id,ganador,confianza) values($1,'W01-TNF','A',16)`,[ANA]);
await allowed('editar su propio pronostico',
  `update picks set ganador='B' where user_id=$1 and game_id='W01-TNF'`,[ANA]);
await allowed('ver el calendario',  `select count(*) from games`);
await allowed('ver el ranking',     `select count(*) from ranking`);
await allowed('ver el historial',   `select count(*) from historial`);
await allowed('registrar underdog', `insert into underdog_picks(user_id,week,opcion) values($1,1,'A')`,[ANA]);
await allowed('canjear folio por RPC (la via correcta)', `select canjear_folio('TEST01')`);
chk('  el canje SI le sumo los puntos',
  (await one(`select pts_consumo from ranking where id=$1`,[ANA])).pts_consumo, 10);
await allowed('cobrar el bono de instalacion por RPC', `select otorgar_bono_instalacion()`);
chk('  el bono SI le sumo los puntos',
  (await one(`select pts_bono from ranking where id=$1`,[ANA])).pts_bono, 25);

console.log('\n== LOS BONOS SOLO LOS MUEVE EL ADMIN ==');
await login(BETO);
await blocked('un jugador NO puede borrar el bono de otro',
  `delete from bonos where user_id=$1`,[ANA]);
await blocked('ni inflarle los puntos a un bono',
  `update bonos set puntos=9999 where user_id=$1`,[ANA]);
// Esta comprobacion va como ADMIN a proposito: desde la sesion de Beto ahora
// devuelve 0 porque no puede ver bonos ajenos, y un 0 aqui no probaria que el
// bono sigue existiendo — solo que no lo ve.
await login(ADMIN);
chk('  el bono de Ana sigue ahi',
  (await one(`select count(*)::int c from bonos where user_id=$1`,[ANA])).c, 1);

console.log('\n== LOS BONOS AJENOS TAMBIEN SON PRIVADOS ==');
// Mismo hueco que tenian los pronosticos: USING (true). Cerrado en
// 006_privacidad_bonos.sql.
//
// Lo que se filtraba aqui no eran los puntos —el ranking ya publica la columna
// pts_bono de todo el mundo— sino el MOTIVO, que lo escribe ADMIN a mano y
// puede decir cualquier cosa: "por ayudar en la cocina", "disculpa por el error
// del lunes". Eso no es dato para que lo lea la banca entera.
await login(BETO);
chk('Beto NO ve los bonos de Ana',
  (await one(`select count(*)::int c from bonos where user_id=$1`,[ANA])).c, 0);
chk('  ni el motivo de nadie mas',
  (await one(`select count(*)::int c from bonos where user_id <> $1`,[BETO])).c, 0);
// La vista `ranking` corre como su dueno y NO pasa por RLS: los totales de
// todos se siguen viendo. Si esto se rompe, desaparece el desglose de puntos.
chk('  pero el ranking SI le muestra los puntos de bono de Ana',
  (await one(`select pts_bono from ranking where id=$1`,[ANA])).pts_bono, 25);
await login(ANA);
chk('Ana si ve los suyos',
  (await one(`select count(*)::int c from bonos where user_id=$1`,[ANA])).c, 1);
await login(ADMIN);
chk('el admin SI ve los de todos (los otorga y responde los reclamos)',
  (await one(`select count(*)::int c from bonos where user_id=$1`,[ANA])).c, 1);

console.log('\n== EL UNDERDOG RESPETA EL TOP 10 ==');
await db.exec(`RESET ROLE`);
await q(`insert into week_snapshots(week,user_id,posicion,total) values (1,$1,1,500),(1,$2,50,10)`,[ANA,BETO]);
await login(ANA);
await blocked('Ana (#1 del corte) NO puede jugar underdog de la semana 2',
  `insert into underdog_picks(user_id,week,opcion) values($1,2,'A')`,[ANA]);
await login(BETO);
await allowed('Beto (#50 del corte) SI puede jugar underdog de la semana 2',
  `insert into underdog_picks(user_id,week,opcion) values($1,2,'B')`,[BETO]);

console.log('\n== LOS PRONOSTICOS AJENOS SON SECRETOS, SIEMPRE ==');
// Este es el hueco que estuvo abierto hasta 005_privacidad_picks.sql: la
// politica decia USING (true), asi que cualquier participante CON sesion leia
// los pronosticos de los otros ~200 antes de que rodara la bola. Con puntos de
// confianza y dinero de por medio, eso es ventaja directa.
//
// No lo cacho nadie porque la unica prueba que existia ("NO puede ver
// pronosticos ajenos") corria como VISITANTE SIN CUENTA, y anon efectivamente
// nunca pudo. El caso que faltaba era este: el participante con sesion.
await db.exec(`RESET ROLE`);
await q(`update games set kickoff = NOW() + interval '3 days' where id='W01-D01'`);
await q(`insert into picks(user_id,game_id,ganador,confianza) values($1,'W01-D01','B',7)`,[BETO]);

await login(ANA);
chk('Ana NO ve el pronostico de Beto',
  (await one(`select count(*)::int c from picks where user_id=$1`,[BETO])).c, 0);
chk('  pero si ve el suyo',
  (await one(`select count(*)::int c from picks where user_id=$1`,[ANA])).c, 1);
chk('Ana NO ve el underdog de Beto',
  (await one(`select count(*)::int c from underdog_picks where user_id=$1 and week=2`,[BETO])).c, 0);

await login(ADMIN);
chk('el admin SI ve los pronosticos de todos (resuelve reclamos de puntaje)',
  (await one(`select count(*)::int c from picks where user_id=$1`,[BETO])).c, 1);

// La privacidad es permanente: ni siquiera cuando ya arranco el partido se
// destapan los ajenos. Decision del dueno de la quiniela.
await db.exec(`RESET ROLE`);
await q(`update games set kickoff = NOW() - interval '1 hour' where id='W01-D01'`);
await login(ANA);
chk('Ana SIGUE sin ver el de Beto aunque el partido ya arranco',
  (await one(`select count(*)::int c from picks where user_id=$1`,[BETO])).c, 0);

// Lo que si se sigue viendo son los TOTALES: la vista `ranking` corre como
// dueno y no pasa por RLS. Si esto se rompe, la tabla de posiciones desaparece.
chk('  y la tabla de posiciones sigue mostrando a todos',
  (await one(`select count(*)::int c from ranking`)).c >= 2, true);

console.log('\n== RUTAS LEGITIMAS PARA CAMBIAR ROLES ==');
await login(ANA);
await allowed('un jugador SI puede editar su nombre/telefono',
  `update profiles set nombre='Ana Maria', tel='8341112233' where id=$1`,[ANA]);
await db.exec(`RESET ROLE`);
await db.exec(`SELECT set_config('request.jwt.claim.sub','',false)`);
await allowed('el editor SQL de Supabase SI puede nombrar al primer admin',
  `update profiles set role='admin' where id=$1`,[BETO]);
chk('  y de verdad quedo admin',
  (await one(`select role from profiles where id=$1`,[BETO])).role, 'admin');
await db.query(`update profiles set role='user' where id=$1`,[BETO]);
await login(ADMIN);
await allowed('un admin SI puede ascender a otro',
  `update profiles set role='manager' where id=$1`,[BETO]);

console.log('\n== EL ADMIN SI PUEDE ==');
await login(ADMIN);
await allowed('cargar marcador',      `update games set score_a=24,score_b=17 where id='W01-TNF'`);
await allowed('cambiar configuracion',`update config set valor='5' where clave='pts_win_normal'`);
await allowed('generar folios',       `select generar_folios('2026-09-13'::date,2)`);
await allowed('cerrar la semana',     `select cerrar_semana(2)`);
await allowed('escribir historial',   `insert into historial(titulo) values('Quiniela NFL 2026')`);
await allowed('dar un bono a mano',   `insert into bonos(user_id,motivo,puntos) values($1,'trivia',15)`,[BETO]);

console.log('\n== UN VISITANTE SIN CUENTA ==');
await db.exec(`RESET ROLE`);
await db.exec(`SELECT set_config('request.jwt.claim.sub','',false)`);
await db.exec(`SET ROLE anon`);
await allowed('puede ver el calendario', `select count(*) from games`);
await blocked('NO puede ver pronosticos ajenos', `select * from picks`);
await blocked('NO puede ver los bonos de nadie', `select * from bonos`);
await blocked('NO puede escribir pronosticos',
  `insert into picks(user_id,game_id,ganador) values($1,'W01-D01','A')`,[ANA]);

await db.exec(`RESET ROLE`);
console.log('\n' + '='.repeat(50));
console.log(`  SEGURIDAD: ${pass} ok  ·  ${fail} fallas`);
console.log('='.repeat(50));
await db.close();
process.exit(fail?1:0);
