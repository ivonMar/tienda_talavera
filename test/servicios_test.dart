import 'package:flutter_test/flutter_test.dart';
import 'package:tienda_talavera/datos/pasarela_simulada.dart';
import 'package:tienda_talavera/dominio/contratos.dart';
import 'package:tienda_talavera/dominio/tarjeta.dart';
import 'package:tienda_talavera/datos/almacenes.dart';
import 'package:tienda_talavera/datos/catalogo_memoria.dart';
import 'package:tienda_talavera/dominio/carrito.dart';
import 'package:tienda_talavera/dominio/direccion.dart';
import 'package:tienda_talavera/dominio/excepciones.dart';
import 'package:tienda_talavera/dominio/servicio_checkout.dart';

const buena = DatosTarjeta(numero: '4242424242424242', titular: 'Ana', mes: 12, anio: 30, cvv: '123');
const rechazada = DatosTarjeta(numero: '4000000000000002', titular: 'Ana', mes: 12, anio: 30, cvv: '123');

const dir = Direccion(
  nombreRecibe: 'Ana Pérez', calle: 'Calle 5 de Febrero 10', colonia: 'Centro',
  codigoPostal: '37800', ciudad: 'Dolores Hidalgo', estado: 'Guanajuato', telefono: '4181234567'
);

void main() {
  group('pasarela simulada', () {
    test('aprueba tarjeta de prueba', () async {
      final r = await PasarelaSimulada().cobrar(
          montoCentavos: 1000, tarjeta: buena, claveIdempotencia: 'k1');
      expect(r, isA<PagoAprobado>());
    });
    test('rechaza tarjeta 0002', () async {
      final r = await PasarelaSimulada().cobrar(
          montoCentavos: 1000, tarjeta: rechazada, claveIdempotencia: 'k1');
      expect(r, isA<PagoRechazado>());
    });
    test('IDEMPOTENCIA: misma clave dos veces cobra una sola vez', () async {
      final p = PasarelaSimulada();
      final a = await p.cobrar(montoCentavos: 1000, tarjeta: buena, claveIdempotencia: 'k1');
      final b = await p.cobrar(montoCentavos: 1000, tarjeta: buena, claveIdempotencia: 'k1');
      expect((a as PagoAprobado).referencia, (b as PagoAprobado).referencia);
      expect(p.cobrosAprobados, 1);
    });
    test('claves distintas sí cobran por separado', () async {
      final p = PasarelaSimulada();
      await p.cobrar(montoCentavos: 1000, tarjeta: buena, claveIdempotencia: 'k1');
      await p.cobrar(montoCentavos: 1000, tarjeta: buena, claveIdempotencia: 'k2');
      expect(p.cobrosAprobados, 2);
    });
  });
  
  group('checkout', () {
    late CatalogoMemoria catalogo;
    late OrdenesMemoria ordenes;
    late PasarelaSimulada pasarela;
    late ServicioCheckout servicio;
    late Carrito carrito;

    setUp(() async {
      catalogo = CatalogoMemoria();
      ordenes = OrdenesMemoria();
      pasarela = PasarelaSimulada();
      servicio = ServicioCheckout(catalogo: catalogo, ordenes: ordenes, pasarela: pasarela,
          reloj: () => DateTime(2026, 11, 5));
      carrito = Carrito()..agregar((await catalogo.porId('jarron'))!);
    });

    test('compra exitosa guarda orden y descuenta inventario', () async {
      final o = await servicio.pagar(usuarioId: 'u1', carrito: carrito, direccion: dir,
          tarjeta: buena, claveIdempotencia: 'k');
      expect(o.total, carrito.total);
      expect(o.tarjetaUltimos4, '4242');
      expect((await catalogo.porId('jarron'))!.existencias, 7);
      expect((await ordenes.delUsuario('u1')).length, 1);
    });

    test('rechazo: sin orden y sin tocar inventario', () async {
      await expectLater(
          servicio.pagar(usuarioId: 'u1', carrito: carrito, direccion: dir,
              tarjeta: rechazada, claveIdempotencia: 'k'),
          throwsA(isA<PagoRechazadoException>()));
      expect((await catalogo.porId('jarron'))!.existencias, 8);
      expect(await ordenes.delUsuario('u1'), isEmpty);
    });

    test('precio cambió: se rechaza ANTES de cobrar', () async {
      catalogo.cambiarPrecio('jarron', 150000);
      await expectLater(
          servicio.pagar(usuarioId: 'u1', carrito: carrito, direccion: dir,
              tarjeta: buena, claveIdempotencia: 'k'),
          throwsA(isA<PrecioCambioException>()));
      expect(pasarela.cobrosAprobados, 0);
    });

    test('tarjeta con Luhn inválido no llega a la pasarela', () async {
      const mala = DatosTarjeta(numero: '4242424242424241', titular: 'A', mes: 12, anio: 30, cvv: '123');
      await expectLater(
          servicio.pagar(usuarioId: 'u1', carrito: carrito, direccion: dir,
              tarjeta: mala, claveIdempotencia: 'k'),
          throwsA(isA<TarjetaInvalidaException>()));
      expect(pasarela.cobrosAprobados, 0);
    });

    test('carrito vacío', () async {
      await expectLater(
          servicio.pagar(usuarioId: 'u1', carrito: Carrito(), direccion: dir,
              tarjeta: buena, claveIdempotencia: 'k'),
          throwsA(isA<CarritoVacioException>()));
    });

    test('dirección inválida', () async {
      const mala = Direccion(nombreRecibe: 'Ana Pérez', calle: 'x', colonia: 'y',
          codigoPostal: '1', ciudad: 'z', estado: 'w', telefono: '1');
      await expectLater(
          servicio.pagar(usuarioId: 'u1', carrito: carrito, direccion: mala,
              tarjeta: buena, claveIdempotencia: 'k'),
          throwsA(isA<DatosInvalidosException>()));
    });
  });
}