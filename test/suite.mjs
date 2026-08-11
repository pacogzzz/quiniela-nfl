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

let pass=0, fail=0;
const q   = async (s,p) => (await db.query(s,p)).rows;
const one = async (s,p) => (await q(s,p))[0];
function chk(name, got, want){
  const ok = JSON.stringify(got)===JSON.stringify(want);
  console.log(`${ok?'  ok  ':'  FALLA'} ${name}${ok?'':`\n         esperado ${JSON.stringify(want)} · obtuve ${JSON.stringify(got)}`}`);
  ok?pass++:fail++;
}
async function shouldFail(name, fn, frag){
  try { await fn(); console.log(`  FALLA ${name}\n         NO falló, y debía fallar`); fail++; }
  catch(e){
    const ok = !frag || e.message.toLowerCase().includes(frag.toLowerCase());
    console.log(`${ok?'  ok  ':'  FALLA'} ${name}${ok?'':`\n         mensaje inesperado: ${e.message}`}`);
    ok?pass++:fail++;
  }
}
const asUser = (id) => db.exec(`SELECT set_config('request.jwt.claim.sub','${id}',false)`);
const dow = async id => one(
  `select trim(to_char(kickoff at time zone 'America/Mexico_City','Day')) d,
          to_char(kickoff at time zone 'America/Mexico_City','YYYY-MM-DD') f
   from games where id=$1`, [id]);

console.log('reloj del sistema:', (await one(`select to_char(now(),'YYYY-MM-DD') d`)).d);

console.log('\n== ESTRUCTURA ==');
chk('32 equipos',             (await one('select count(*)::int c from teams')).c, 32);
chk('301 partidos',           (await one('select count(*)::int c from games')).c, 301);
chk('288 de temporada regular',(await one('select count(*)::int c from games where week<=18')).c, 288);
chk('13 de playoffs',         (await one('select count(*)::int c from games where week>=19')).c, 13);
chk('22 semanas de underdog', (await one('select count(*)::int c from underdog_weeks')).c, 22);
chk('12 llaves de config',    (await one('select count(*)::int c from config')).c, 12);
chk('32 politicas RLS',       (await one("select count(*)::int c from pg_policies where schemaname='public'")).c, 32);
chk('RLS activo en 12 tablas',(await one("select count(*)::int c from pg_tables t join pg_class k on k.relname=t.tablename where t.schemaname='public' and k.relrowsecurity")).c, 12);

console.log('\n== FECHAS SEMBRADAS ==');
const w1=await dow('W01-TNF'),  tg=await dow('W12-TG1'), bf=await dow('W12-BF1');
const nv=await dow('W16-NAV1'), sbw=await dow('W22-SB'), w18=await dow('W18-D01');
chk('W1 TNF = jueves 10-sep-2026',        [w1.d,w1.f],   ['Thursday','2026-09-10']);
chk('Thanksgiving = jueves 26-nov-2026',  [tg.d,tg.f],   ['Thursday','2026-11-26']);
chk('Black Friday = viernes 27-nov-2026', [bf.d,bf.f],   ['Friday','2026-11-27']);
chk('Navidad = viernes 25-dic-2026',      [nv.d,nv.f],   ['Friday','2026-12-25']);
chk('Semana 18 = domingo 10-ene-2027',    [w18.d,w18.f], ['Sunday','2027-01-10']);
chk('Super Bowl = domingo 14-feb-2027',   [sbw.d,sbw.f], ['Sunday','2027-02-14']);

console.log('\n== AUTO-FLAGS (mie/vie/sab = 15 pts) ==');
chk('Black Friday especial',      (await one("select is_special s from games where id='W12-BF1'")).s, true);
chk('Navidad especial',           (await one("select is_special s from games where id='W16-NAV1'")).s, true);
chk('sabado 19-dic especial',     (await one("select is_special s from games where id='W15-SAB1'")).s, true);
chk('Thanksgiving NO especial',   (await one("select is_special s from games where id='W12-TG1'")).s, false);
chk('Thanksgiving SI estelar',    (await one("select is_stellar s from games where id='W12-TG1'")).s, true);
chk('domingo normal NO especial', (await one("select is_special s from games where id='W01-D01'")).s, false);
chk('TNF estelar',                (await one("select is_stellar s from games where id='W01-TNF'")).s, true);
chk('domingo temprano NO estelar',(await one("select is_stellar s from games where id='W01-D01'")).s, false);
chk('ningun jue/dom/lun marcado especial',
  (await one("select count(*)::int c from games where is_special and extract(dow from kickoff at time zone 'America/Mexico_City') in (0,1,4)")).c, 0);

console.log('\n== PUNTOS: CONFIANZA + ANOTADOR (additive) ==');
const U1=(await one(`insert into auth.users(email) values('a@x.com') returning id`)).id;
const U2=(await one(`insert into auth.users(email) values('b@x.com') returning id`)).id;
await q(`insert into profiles(id,nombre,email) values($1,'Ana','a@x.com'),($2,'Beto','b@x.com')`,[U1,U2]);
await q(`update games set team_a='DAL',team_b='PHI' where id='W01-TNF'`);
await q(`update games set team_a='KC', team_b='LV'  where id='W01-D01'`);
await q(`update games set team_a='GB', team_b='CHI' where id='W12-BF1'`);
await asUser(U1);
await q(`insert into picks(user_id,game_id,ganador,confianza,primero) values($1,'W01-TNF','A',16,'A')`,[U1]);
await q(`insert into picks(user_id,game_id,ganador,confianza) values($1,'W01-D01','A',15)`,[U1]);
await q(`insert into picks(user_id,game_id,ganador,confianza) values($1,'W12-BF1','B',1)`,[U1]);
await q(`update games set score_a=24,score_b=17,first_scorer='A' where id='W01-TNF'`);
await q(`update games set score_a=10,score_b=20 where id='W01-D01'`);
await q(`update games set score_a=13,score_b=27 where id='W12-BF1'`);
const r1 = await one(`select * from ranking where id=$1`,[U1]);
// conf_mode = 'solo': acertar paga TU numero de confianza y nada mas.
// TNF acertado con 16 · D01 fallado con 15 · BF1 acertado con 1 = 17.
chk('confianza = 16 + 0 + 1 = 17', r1.pts_confianza, 17);
chk('anotador = 3',   r1.pts_anotador, 3);
chk('total = 20',     r1.total_puntos, 20);

console.log('\n== EMPATE NO DA PUNTOS ==');
await q(`update games set team_a='NE',team_b='NYJ',score_a=20,score_b=20 where id='W01-D02'`);
await q(`insert into picks(user_id,game_id,ganador,confianza) values($1,'W01-D02','A',14)`,[U1]);
chk('empate = 0 pts', (await one(`select pts_confianza from ranking where id=$1`,[U1])).pts_confianza, 17);

console.log('\n== CONFIANZA REPETIDA SE RECHAZA ==');
await shouldFail('indice unico bloquea duplicado',
  ()=>q(`insert into picks(user_id,game_id,ganador,confianza) values($1,'W01-D03','A',16)`,[U1]), 'unique');
chk('guardar_semana rechaza duplicados',
  (await one(`select guardar_semana(1,'[{"game_id":"W01-D04","confianza":"3"},{"game_id":"W01-D05","confianza":"3"}]'::jsonb) r`)).r.msg,
  'Hay valores de confianza repetidos');
chk('guardar_semana rechaza fuera de rango',
  (await one(`select guardar_semana(1,'[{"game_id":"W01-D04","confianza":"99"}]'::jsonb) r`)).r.msg,
  'La confianza debe ir de 1 a 16');
chk('guardar_semana rechaza partido de otra semana',
  (await one(`select guardar_semana(1,'[{"game_id":"W12-BF1","confianza":"2"}]'::jsonb) r`)).r.msg,
  'Hay partidos que no son de esta semana');

console.log('\n== REORDENAR CONFIANZA (swap 16 <-> 15) ==');
const swap = await one(`select guardar_semana(1,'[{"game_id":"W01-TNF","ganador":"A","confianza":"15","primero":"A"},{"game_id":"W01-D01","ganador":"A","confianza":"16"}]'::jsonb) r`);
chk('el intercambio funciona', swap.r.ok, true);
chk('TNF quedo en 15', (await one(`select confianza c from picks where user_id=$1 and game_id='W01-TNF'`,[U1])).c, 15);
chk('D01 quedo en 16', (await one(`select confianza c from picks where user_id=$1 and game_id='W01-D01'`,[U1])).c, 16);

console.log('\n== BORRAR UN PRONOSTICO LO LIMPIA DE VERDAD ==');
await one(`select guardar_semana(1,'[{"game_id":"W01-TNF","ganador":"","confianza":"","primero":""}]'::jsonb) r`);
const limpio = await one(`select ganador,confianza,primero from picks where user_id=$1 and game_id='W01-TNF'`,[U1]);
chk('queda en null', [limpio.ganador,limpio.confianza,limpio.primero], [null,null,null]);
await one(`select guardar_semana(1,'[{"game_id":"W01-TNF","ganador":"A","confianza":"16","primero":"A"}]'::jsonb) r`);

console.log('\n== CIERRE POR KICKOFF ==');
await q(`update games set kickoff = now() - interval '2 hours' where week=3`);
await shouldFail('trigger bloquea pick tras kickoff',
  ()=>q(`insert into picks(user_id,game_id,ganador) values($1,'W03-TNF','A')`,[U1]), 'cerrado');
chk('guardar_semana bloquea semana cerrada',
  (await one(`select guardar_semana(3,'[{"game_id":"W03-TNF","ganador":"A"}]'::jsonb) r`)).r.msg,
  'La semana 3 ya cerro'.replace('cerro','cerró'));

console.log('\n== FOLIOS DE CONSUMO ==');
chk('lunes vale 10',     (await one(`select puntos_por_fecha('2026-09-14'::date) p`)).p, 10);
chk('domingo vale 5',    (await one(`select puntos_por_fecha('2026-09-13'::date) p`)).p, 5);
chk('jueves vale 5',     (await one(`select puntos_por_fecha('2026-09-10'::date) p`)).p, 5);
// El día raro vale MÁS que un domingo: es el que cuesta llenar el restaurante.
chk('viernes vale 15',   (await one(`select puntos_por_fecha('2026-11-27'::date) p`)).p, 15);
// Nombrar admin va por la ruta legitima: sin sesion, como el editor SQL de Supabase
await db.exec(`SELECT set_config('request.jwt.claim.sub','',false)`);
await q(`update profiles set role='admin' where id=$1`,[U1]);
await asUser(U1);
const gen = await one(`select generar_folios('2026-09-14'::date,3) r`);
chk('genera 3 folios',   gen.r.codes.length, 3);
chk('valen 10 c/u',      gen.r.puntos, 10);
const [f1,f2] = gen.r.codes;
await asUser(U2);
chk('canje ok',              (await one(`select canjear_folio($1) r`,[f1])).r.ok, true);
chk('mismo folio 2a vez',    (await one(`select canjear_folio($1) r`,[f1])).r.msg, 'Ese folio ya fue canjeado');
const dos = await one(`select canjear_folio($1) r`,[f2]);
chk('2o folio el mismo dia se rechaza', dos.r.ok, false);
chk('  con mensaje de uno-por-dia', dos.r.msg.includes('uno por'), true);
chk('folio inexistente',     (await one(`select canjear_folio('NOPE') r`)).r.msg, 'Folio inválido');
chk('Beto: 10 pts de consumo',(await one(`select pts_consumo from ranking where id=$1`,[U2])).pts_consumo, 10);

console.log('\n== UNDERDOG ==');
await q(`update games set team_a='CAR',team_b='SF',score_a=30,score_b=7 where id='W01-D06'`);
await q(`update underdog_weeks set opt_a_game='W01-D06',opt_a_team='CAR' where week=1`);
await q(`insert into underdog_picks(user_id,week,opcion) values($1,1,'A')`,[U2]);
// Cada opción paga lo suyo: A vale 8, no el tope de la week.
chk('underdog acertado = +8 (opción A)', (await one(`select pts_underdog from ranking where id=$1`,[U2])).pts_underdog, 8);
chk('detecta al perdedor',     (await one(`select underdog_acierto('W01-D06','SF') a`)).a, false);
// Las tres puertas NO pagan igual: es lo que hace que escoger sea una decisión.
await q(`update underdog_picks set opcion='C' where user_id=$1 and week=1`,[U2]);
await q(`update underdog_weeks set opt_c_game='W01-D06',opt_c_team='CAR' where week=1`);
chk('la opción C paga 12, no 8', (await one(`select pts_underdog from ranking where id=$1`,[U2])).pts_underdog, 12);
// Y si una week vieja no trae valores por opción, se sigue pagando `puntos`.
await q(`update underdog_weeks set puntos_c=null, puntos=20 where week=1`);
chk('sin puntos_c cae en el respaldo', (await one(`select pts_underdog from ranking where id=$1`,[U2])).pts_underdog, 20);
await q(`update underdog_weeks set puntos_c=12, puntos=12 where week=1`);
await q(`update underdog_picks set opcion='A' where user_id=$1 and week=1`,[U2]);
await q(`update underdog_weeks set opt_c_game=null, opt_c_team=null where week=1`);

console.log('\n== ELEGIBILIDAD DEL UNDERDOG (corte del lunes) ==');
chk('sin cortes, todos elegibles', (await one(`select underdog_elegible($1,1) e`,[U1])).e, true);
await asUser(U1);
chk('cerrar_semana ok', (await one(`select cerrar_semana(1) r`)).r.ok, true);
chk('2 snapshots creados', (await one(`select count(*)::int c from week_snapshots where week=1`)).c, 2);
const pos = await q(`select p.nombre,p.id,s.posicion from week_snapshots s join profiles p on p.id=s.user_id where s.week=1 order by s.posicion`);
console.log('        corte semana 1:', pos.map(r=>`#${r.posicion} ${r.nombre}`).join('   '));
await q(`update config set valor='1' where clave='underdog_top_n'`);
chk(`#1 (${pos[0].nombre}) NO puede underdog en sem.2`, (await one(`select underdog_elegible($1,2) e`,[pos[0].id])).e, false);
chk(`#2 (${pos[1].nombre}) SI puede underdog en sem.2`, (await one(`select underdog_elegible($1,2) e`,[pos[1].id])).e, true);
await q(`update config set valor='10' where clave='underdog_top_n'`);

console.log('\n== conf_mode CAMBIA EL PUNTAJE EN CALIENTE ==');
await q(`update config set valor='flat' where clave='conf_mode'`);
chk('flat: 5 + 15 = 20',      (await one(`select pts_confianza from ranking where id=$1`,[U1])).pts_confianza, 20);
await q(`update config set valor='solo' where clave='conf_mode'`);
chk('solo: 16 + 1 = 17',      (await one(`select pts_confianza from ranking where id=$1`,[U1])).pts_confianza, 17);
await q(`update config set valor='additive' where clave='conf_mode'`);
chk('additive: 21 + 16 = 37', (await one(`select pts_confianza from ranking where id=$1`,[U1])).pts_confianza, 37);
// Se deja en 'solo', que es el modo oficial de la temporada.
await q(`update config set valor='solo' where clave='conf_mode'`);

console.log('\n== BONOS (puntos a mano) ==');
// Beto viene con 18 (10 de consumo + 8 del underdog A) y sin un solo bono.
chk('sin bonos, pts_bono = 0',  (await one(`select pts_bono from ranking where id=$1`,[U2])).pts_bono, 0);
await asUser(U2);
const b1 = await one(`select otorgar_bono_instalacion() r`);
chk('bono de instalacion = 25', [b1.r.ok, b1.r.ya, b1.r.puntos], [true, false, 25]);
const b2 = await one(`select otorgar_bono_instalacion() r`);
chk('no se cobra dos veces',    [b2.r.ok, b2.r.ya, b2.r.puntos], [true, true, 0]);
chk('y solo quedo 1 fila',      (await one(`select count(*)::int c from bonos where user_id=$1 and motivo='instalacion'`,[U2])).c, 1);
chk('el bono llega al ranking', (await one(`select pts_bono from ranking where id=$1`,[U2])).pts_bono, 25);
chk('y suma al total: 18+25',   (await one(`select total_puntos from ranking where id=$1`,[U2])).total_puntos, 43);
// El monto sale de config, no esta hardcodeado en la funcion
await q(`update config set valor='50' where clave='pts_bono_instalacion'`);
await asUser(U1);
chk('respeta el valor de config',(await one(`select otorgar_bono_instalacion() r`)).r.puntos, 50);
// Solo 'instalacion' es unico; los demas motivos si se pueden repetir
await q(`insert into bonos(user_id,motivo,puntos) values($1,'trivia',10)`,[U2]);
await q(`insert into bonos(user_id,motivo,puntos) values($1,'trivia',10)`,[U2]);
chk('otros motivos si se repiten',(await one(`select pts_bono from ranking where id=$1`,[U2])).pts_bono, 45);
await shouldFail('el indice unico bloquea 2o bono de instalacion',
  ()=>q(`insert into bonos(user_id,motivo,puntos) values($1,'instalacion',25)`,[U2]), 'duplicate key');

console.log('\n== ENTRAR CON USUARIO Y CONTRASENA ==');
await q(`update profiles set usuario='PacoG' where id=$1`,[U1]);
chk('encuentra el correo por usuario',
  (await one(`select correo_de_usuario('PacoG') c`)).c, 'a@x.com');
chk('no importan mayusculas ni espacios',
  (await one(`select correo_de_usuario('  pacog ') c`)).c, 'a@x.com');
chk('usuario que no existe devuelve nada',
  (await one(`select correo_de_usuario('nadie') c`)).c, null);
chk('usuario ocupado NO esta disponible',
  (await one(`select usuario_disponible('PACOG') d`)).d, false);
chk('usuario libre SI esta disponible',
  (await one(`select usuario_disponible('otro') d`)).d, true);
await shouldFail('dos personas no pueden tener el mismo usuario',
  ()=>q(`update profiles set usuario='pacog' where id=$1`,[U2]), 'duplicate key');
chk('sin usuario asignado no estorba (puede haber varios NULL)',
  (await one(`select count(*)::int c from profiles where usuario is null`)).c, 1);

console.log('\n== ORDEN DEL RANKING ==');
const rank = await q(`select nombre,total_puntos from ranking`);
console.log('        ', rank.map(r=>`${r.nombre}=${r.total_puntos}`).join('   '));
chk('de mayor a menor', rank[0].total_puntos >= rank[1].total_puntos, true);

console.log('\n== ESCALERA DE NIVELES DE RACHA ==');
chk('0 semanas = nivel 0',   (await one(`select racha_nivel_de(0) n`)).n, 0);
chk('2 semanas = nivel 0',   (await one(`select racha_nivel_de(2) n`)).n, 0);
chk('3 semanas = nivel 1',   (await one(`select racha_nivel_de(3) n`)).n, 1);
chk('7 semanas = nivel 1',   (await one(`select racha_nivel_de(7) n`)).n, 1);
chk('8 semanas = nivel 2',   (await one(`select racha_nivel_de(8) n`)).n, 2);
chk('13 semanas = nivel 3',  (await one(`select racha_nivel_de(13) n`)).n, 3);
chk('18 semanas = nivel 4',  (await one(`select racha_nivel_de(18) n`)).n, 4);
chk('22 semanas = nivel 4',  (await one(`select racha_nivel_de(22) n`)).n, 4);
chk('23 semanas = nivel 5 (18+5, se repite)', (await one(`select racha_nivel_de(23) n`)).n, 5);
chk('28 semanas = nivel 6 (18+10)',           (await one(`select racha_nivel_de(28) n`)).n, 6);
chk('premio nivel 1', (await one(`select racha_premio_de(1) p`)).p, 'Promo 3x2 de cortesía');
chk('premio nivel 2', (await one(`select racha_premio_de(2) p`)).p, 'Entrada + Promo 3x2 de cortesía');
chk('premio nivel 3', (await one(`select racha_premio_de(3) p`)).p, 'Descuento 15%');
chk('premio nivel 4', (await one(`select racha_premio_de(4) p`)).p, 'Descuento 25%');
chk('premio nivel 7 (se repite el de nivel 4)', (await one(`select racha_premio_de(7) p`)).p, 'Descuento 25%');

console.log('\n== RACHA DE SEMANAS Y SUS CODIGOS ==');
// Semanas 6,7,8 nuevas (nadie las ha tocado): un pronóstico de U1 en cada
// una, y DESPUÉS se les mueve el kickoff al pasado -- en ese orden, porque
// el trigger ya bloquea escribir picks de una semana que arrancó.
for (const w of [6,7,8]) {
  await q(`insert into picks(user_id,game_id,ganador)
           select $1, id, 'A' from games where week=$2 limit 1`, [U1, w]);
}
await q(`update games set kickoff = now() - interval '3 days' where week=6`);
await q(`update games set kickoff = now() - interval '2 days' where week=7`);
await q(`update games set kickoff = now() - interval '1 days' where week=8`);
// La semana 3 también está "arrancada" (se movió arriba) y ahí U1 NO tiene
// pronóstico: por diseño, la racha para en la primera semana ya arrancada
// sin pronóstico, así que 6-7-8 cuentan como 3 seguidas y ahí se corta.
chk('racha_semanas_de(U1) = 3', (await one(`select racha_semanas_de($1) r`,[U1])).r, 3);

await asUser(U1);
const rc1 = await one(`select reclamar_racha() r`);
chk('reclamar_racha detecta 3 semanas', [rc1.r.ok, rc1.r.racha, rc1.r.nivel], [true, 3, 1]);
chk('otorga exactamente 1 código nuevo', rc1.r.nuevos.length, 1);
chk('el código es del nivel 1 con su premio', [rc1.r.nuevos[0].nivel, rc1.r.nuevos[0].premio],
  [1, 'Promo 3x2 de cortesía']);
const rc2 = await one(`select reclamar_racha() r`);
chk('llamarla otra vez no duplica códigos', rc2.r.nuevos.length, 0);
chk('sigue habiendo solo 1 fila para U1',
  (await one(`select count(*)::int c from racha_premios where user_id=$1`,[U1])).c, 1);

console.log('\n== CANJEAR UN CÓDIGO DE RACHA ==');
const codigo = rc1.r.nuevos[0].codigo;
await asUser(U2); // Beto es jugador normal, no admin/manager
chk('un jugador normal NO puede canjear',
  (await one(`select canjear_codigo_racha($1) r`,[codigo])).r.msg, 'Sin permiso');
await asUser(U1); // U1 se volvió admin en la sección de FOLIOS
const canje = await one(`select canjear_codigo_racha($1) r`,[codigo]);
chk('admin sí puede canjear', [canje.r.ok, canje.r.premio], [true, 'Promo 3x2 de cortesía']);
const otraVez = await one(`select canjear_codigo_racha($1) r`,[codigo]);
chk('el mismo código no se puede volver a canjear', otraVez.r.ok, false);
chk('  con el aviso de ya canjeado', otraVez.r.msg.includes('Ya se canjeó'), true);
chk('código que no existe', (await one(`select canjear_codigo_racha('RACHA-NOPE') r`)).r.msg,
  'Código no encontrado');

console.log('\n' + '='.repeat(50));
console.log(`  RESULTADO: ${pass} ok  ·  ${fail} fallas`);
console.log('='.repeat(50));
await db.close();
process.exit(fail?1:0);
