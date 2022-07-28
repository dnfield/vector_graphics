// Copyright 2013 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_graphics/vector_graphics.dart';
import 'package:vector_graphics_codec/vector_graphics_codec.dart';
import 'package:vector_graphics_compiler/vector_graphics_compiler.dart';

import 'test_svg_strings.dart';

class TestBytesLoader extends BytesLoader {
  const TestBytesLoader(this.data);

  final ByteData data;

  @override
  Future<ByteData> loadBytes(BuildContext context) async {
    return data;
  }

  @override
  int get hashCode => data.hashCode;

  @override
  bool operator ==(Object other) {
    return other is TestBytesLoader && other.data == data;
  }
}

void main() {
  setUpAll(() {
    if (!initializePathOpsFromFlutterCache()) {
      fail('error in setup');
    }
  });

  testWidgets('Can endcode and decode simple SVGs with no errors',
      (WidgetTester tester) async {
    for (final String svg in allSvgTestStrings) {
      final Uint8List bytes = await encodeSvg(
        xml: svg,
        debugName: 'test.svg',
        warningsAsErrors: true,
      );

      await tester.pumpWidget(Center(
          child: VectorGraphic(
              loader: TestBytesLoader(bytes.buffer.asByteData()))));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('Errors on unsupported image mime type',
      (WidgetTester tester) async {
    const String svgInlineImage = r'''
<svg width="248" height="100" viewBox="0 0 248 100">
<image id="image0" width="50" height="50" xlink:href="data:image/foobar;base64,iVBORw0KGgoAAAANSUhEUgAAAkoAAACqCAYAAABS+GAyAAAACXBIWXMAAAsSAAALEgHS3X78AAAaD0lEQVR4nO3da4wd1WHA8TP3rnlVzW6gogIUdlVFQSRRvSlNv6VeolYJT6+JIahSxSJFEV8qjPqh/cb6W6UWsXyqGqVlLbVKAgbbqQqtmmA7PA1ts2552g71QhNjG5NdjF/43jvV3D1nPb5779w5Z86cOTPz/ykbDHsfs3PXe/975syZIAxDAXuefL/dePZIe3s7DDcNe9Cse37Y/Yc+/pAbqE8HQjy18bqRe+7+XLOjsXkAAJReg5fQHhVJHRFuCoISbHCKbSSSAAB1RihZEo+kSnxBRBIAAGKEXZCdr5EUZDi8FwTi6TuvJZIAAPXGiFJGlRxJWomku4kkAEDdEUoZFB1JeUyDIpIAALiAUDLESBIAANVHKBkgkgAAqAcmc2vqRtIH7ac6Ipwu1YYnIJIAAOiPESUNq5EUEkkAANQBI0opVTGSGkI8fQeRBADAQIwopUAkAQBQT4TSEEQSAAD1RSglIJIAAKg3QmkAIgkAABBKfRBJAABAEEprRZH0b0QSAAC1Jwili6lIahNJAADUnmAdpQuqGkm3E0kAABhjRKnEkRQmfI5IAgAgu9qHEiNJAAAg4T21vgZFUtJIje+IJAAA7KltKDGSBAAAUry31o+LSAodD0sRSQAA2Fe7UGIkCQAAaLzH1odPkWRrwIlIAgAgP7UJpbSRVKaJ3EQSAAD5qsWCkxcuSyKqc7gtEDtuu4ZIAgAgT5UfUapwJG0mkgAAyFelQ6k3kkJHB9byPOONSAIAwJ3KhpLJSJLv85OIJAAA3KpkKPl+uM0kyIgkAADcq1woDYokV4fd8kAkAQBQjEqFUpaRJFsZZXt+EpEEAEBxKhNKSZFU1tEkIgkAgGJVIpTKtARA2mQjkgAAKF7pQ2lYJKUZTfJtvIlIAgDAD6UOJd9GkmzMTyKSSieswccezRdlVnOfzNb9mwiAv0obSmkiybfRpGHPRSQBAOCXUoYSlyUBAAAulC6U0kaS6zPdshx2I5IAAPBTqULJ9kiSD4fdiCQAAPxVmlDSiaSyjCYRSQAA+K0UoZRHJBW9JACRBACA/7wPpTwmbruOpN7nI5IAACiHEZ+3UjeSirhUie5hNyIJgIdmhBATGps1L4Q47NmXobseF+t3IRVvQymvSCrykBuRBMBTUSht0Ni0PR6G0sOatyeUkIqXh97Ksk5SmtEkdRMiCQCA8vFuRMkkknwfTSKSEHNzCXfGkgfbAACF8CqUyhRJaUeTiCT00L1uGgCgQN4cesszkopCJAEAUG5ehFLekVTEaFJAJAEAUHqFH3orWySlEY0k3UokAQBQeoWOKJUxkoaNJhFJAABUR2GhRCQBAADfFRJKHG4DAABl4DyUynp2W9JoEpEEAEA1OZ3M7eLaba6TikgCAKC6nI0olTmSBo0mEUkAAFSbkxElnUgyPcxGJAEAANtyD6W8IynPQ21EEgAA9ZZrKKWNJN9GkZIQSQAA1EduoZQmkrKczZZ3JPUbTSKSAACol1xCaVgkZT3dn0gCAEBMyI8puSumEnbJkhBiQf55jxDisPyok2j/TMp9Npmwj9RHd/9YD6WkSPI9kASRBADw15gQ3ffWKfkxrrmlG+U/H5b/XJRBsFN+LFXwtZ+OfYymuP3G2J/3CyHmrYZSv0iytVgkkQQgJvqNcEZjh0S/Gc57tgPz/BpmDbZFx8yQ0Ys09siPQdujs29M6O6jfuYdjcpMyf1xn+XHHZcfURw8LoTYJYPJ5d8Vndch6Xum14x8bN2YjFsvhHjUWijFI8n2StpFrctNJAHemoj9VpzGXk9DKa+vQedxTdh6w04Kpby/BhuPvyfnUIre7LfIN2wXNsqPudhH3qNMuq/DsFCakn9PsgTSRawsOKkiqR2GViMpdBhJvaNJRBIAoCCTMggedxhJcaMyYKII3FKSb4IxORq222YkCRuhFI8kO5vkNpAEkQQA8MOYHMn5uRBigwdbFAXTo3IeU7/Jz76YlNu4MY/tyRRKtiPJdSAJIgkA4Ac1ivSgh6/Herltec8bM6H2m9VRpDjjULIZSUUEkiCSAAB+mJZv9kUcZktrVB4K9Gmun4qkNGezGTMKJVuRVFQgCSIJAOCHaJRmR95v9hbdJw9zjRW8HU4iSZiEko1IKjKQBJEEAPDDrBylKRt1KK6oWBqTI1tO4lIrlLJEUuhBIAkiCQDghxkHSyDkab3Gmka2zbo8TJl6HSWTSCo6iuJYTBIA4IkZiyNJy/JQ2B75T7Xu0YJcj0qN+sQvd2LrjLr1cmTH5STvCdcT3lOFUtpI8imM4ogkAIAnJi1F0i4ZKTsTbrOQ8Dl1aY+si4eqOUtzGR8nLdMV1eNBKWJBqUJSXQNuzUjV0FDqF0m+BlE/RBKAGrpZ80ue0zyU8dCQN+E0kla0XjD4GnZr3l738fvR3QdjFg5X7ZKLQGZdEVxd322LjI8sozSPxka08jQh407HttjXmsaYHHVbjcjEUIoi6dnuZUnsLSbpEpEEoKZ034x1L1OxkPP8lCUH81+KmF+TZQLyojzEZXu7l2QszcsP07k/8w4WpdQZ/TINyqWeiJwZGEpljqR+gSQcRtID+07feFY0/yz6cycMg4s3TgSD7heGg7ZcT9oHSfNsYXeLg3D0o48e+tvbr/3UxvYBQA1NZ1g5eq+8f57XXVOrb88bHo5bL0embFxsOItlGZRpR5CSRPt7rm8oEUnmHth35sbTovnm6vYEPV00IJPCpE+uvWHWm2gdPm2cPvMlIgkAjI1lWKhxm+PJ0jOx68zp2iLcXEh3kP0yKK1eqHjN8gBljaQokPyIpMaFSEp5v9TRUkAkBSdPffkfvz72ZoqbAgD622J4yM11JClR1N1vcL/RAi+iu1/OLbIaSaI3lMocSYNUJpIcP1Z32z5c/t1/+uMr37D8sABQJ2OG8bC34GurRbH0mMH9thSwEKWKpFxGslZDqYyRlDSKJEoQSVosPWjah2kf+XD9D26/+n/sPCt6XgLfP6Z4wQBrTEaTFg3O7spDtO17NR/X9ajSct7zt7qhVNZISuIskl41jyTXh9zS+vT/jk3+aNN1/23xIQGgjkxHk2YKnOfTy2RUy+VImPU5Sb0aZYukYaNIwnUkheWJpDS3+3Txg69s3/y5/SkfEgAw2IzBaNJjBV4apJ/Dcq6UjnFHI2LbXOyrlUNvof9rSKYJJFG1SLIozXOeOfj+Tdu/PZ73gmEAUBe6o0nLHpxe34/JNuUdSsuuDvE1oqC45Zrm5oYIdrh4Ql1pA0lUMZIcHnI7887i7+/408//l6WHA4C6m5QjKzqKPLU+icmoUt6h5GxfdUeUfIslFUc6yy+WIZK0ODzkdvqtw1/dcd8X/tPm5gNAzZnM03F1vTQTugs4juZ4Ysiyy321etabD7GkG0dKWSLJ5rwkWw/1yevv/sHO+2/4D3vPCAAwiIRtno4mKTtloOjIK5R2utxXF62jVEQsmYwexVUukhw+XhRJP/7Oja9Z3jQAqLu+V6EfwsYlN/Kmu415hpIza1bmdhFLWeNIqWQkOTrkRiQBQG50A2G5JKGke7JPHhfJdb6v1oSSyCmWbMWRQiSZ345IAoBc6QZCGSJJGITSaA6rdDs/M7tvKImMsRSPIptxpNQ1kmwgkgAgd7qh5NO6SUlMIsX2qJLzfTWS9EkZIpufPdLe3hHhpt7P2w6gNIIaR1LW0SQiyQtbS7CNua5yC9TABs0vcUvB13XL04Tlx3Y+opQYSiIWS88caW3vhGJNLLkSypGk20pw7TYiCQl8XEwOgD0mYaA78btMbIeS8zMDBx56i4vCJBrFiULF2Zb1XDXUVSR996VTX1SRFJYskgYhkgDAGdthgIKlCiXhOJZ6A8VlJJ1tjrwhDOOk6Ejqd1siCQCcsj15uezyOPPNqdShJHKOpXDACA6RZH5bIgkAnCt9GFhW+nDUCiVhOZYGxdHqxjmKpFt3n77lrbONN1qhP5GU9SGJJAAAstMOJZEhlsIUcaS4jKTjreCZMy0h3jvVEW2NkNGew6T52Ka3I5IAALDDKJREyljSCaM4V5F0296z34wiSS1zcLadPpa0B4ZyiKR+iCQAAOwxDiURi6VobaPeKDJ9s3cZSUfPhc/2rgWVJpZ8iaTe2xJJAADPlH5dtkyhJGQs3WZpzpLLw21RJA36fFIsEUkAAKRW+lAauuBkGmpRyn/JsCily0g6dj54ZtjtVCxd/xsN0QwMR8iIJABAsm1CiPkK7yPnK2nbZiWURMZY8i2SlHgsNQLNJyOSAADDHS7Rtd5qKfOhtziTw3Au5yTpRJJypi3E4qmO6GRd1Cj7TYkkAPCf7gjKFK+p36yGktCMJdcTt3XuE5+QflYnlogkAOmwgnM16V6LjO8Dz1kPJZEylnyPpF6pYolIApAeKzhXk+7k5SpfELcScgklMSSWfI2kYcsaDIwlzfUQiCQAqCyTs7yIZo/lFkpiQCz5HElprIklzdPhiCQAEnNTqmuv5lfG94LHcg0l0RNLPkaSyeKYKpbaGl+F7vMQSUDlTfASVxYTuivE2vIASdTSAeLCn3OTNpKyXCYkVGfDne6I8StW1lmy+VxEElB5USSN8zJXlm4obZSTunUngsOB3EeUlCiQqhJJylkZSzYvd0IkAbnwbQ7ItAfbgPyYrIvE94SnnIVS3tJEUpZr0A26b1IsEUmAN0Y9eylmPNgG5Cea0L1f89H5nvBUJUJpWCRlCSSR4r79YolIArzjyzyQCU4JrwXdUaUNzFXyU+lDKSmSbASS1tlwpzuiFRJJgAMmhzZ8Ofw268E2IH8m128rw/fGjJxLNVuXxTJLHUqDIilrIAnD+6+eDZdhTSUiCciND7+tR6NJ93mwHcjfgsHhtw2ez1WKwmhOHsp+WB5irHwwlTaUeiMptBhIWR7jXCd9LBFJQCa6a9Vs9OAHelVGk7jsRjpzBveZ93j/zvfM96tFMJUylOKRZCOObD6OSBlLRBKQmckKyEX+tj5VodGkKqwk7eJriMJiWfM+o4aH7fK2Rf6yMWibVTDNVW2NsNKF0q27T9/ywbnwWZthY+tx4gbFUr/tJpIAIybzlIoa0Rnz9M3PVBVGDlx9DSajShs9G32MovLRFLeLgulBIcT/ej4ypqVUofTNPWe+cfR88Iytx7MZW/30xlK/5yKSAGMmoTRe0GnYOyu2wGQVzs5y9TXMGYwqCTlC48OSAZOGf9cqcwZfaUIpiqTjn4p/tfFYeQdSnIqlVp8nJJKATKJh/kWDB3B9aGBeTtL1me5K0usrcHjF1WHYJXnYysTjBceSiiSTdchmq7LSeClCyVYkuQyk1ecM+58NRyQBVuw0eJBReT8XhwXmSzIvyeQNzbcFEnUn97uMvXmDM+CUxw0P32U1lSGS9lbpULP3oWQjkooIJCEjSTkXiyUiCbDG9IfxevkmkFcsjcnHL8vkbd0RJSFHSXyag2ISey4DJEtYPii/n1yFXTQatNswkpartsq496F0qhP8vel9iwok0RNJShRLr/xk37unn3vZ5IcSgLUWDEYSFBVLts9+mpKHBX0/3BZn8jPJt7OzTObRbHT4ph7t460Z7r9BPkaep+FPyed4OMNjzBqekeot70Pp61c3x68YCX6Z9va21lMyFQVSv0iKHN332vnjB37xO68G4p//6E/+YV1BmwhUTZY36yiWfm7pzWdCHtIz/U28SKbzvTYajszN5PBmahJKQh7a0j3DbEzeR3fu0WyGsBc5rls0Jf8e7c54eZ1tBR0mzJX3obT1y+va3VhqisRYKjKOVrchYQOiSFo6+ItuHLUawTf2NcSP73zgByMONw+oqizzPxT15jOvOcI0Jt/0d8pTogetM9PProxvmraZzPcScqRDvXEnHRqakGFxWMaJ7bMAFwxjT8Re/5kh8TEpQ+CwvI9JqExb+H5VwfRr+boN2+5+JuXrsSADKeth4v0ZJq17LQiT3t098vDr55vPHW29d7otrlVb5cuWD9uF8UiKC9rhM5cdPH7nidf+op3/ViInut+GQQ1eiFnNofutFtaMmZI/7G1Zlm8gapRiSf67OuV5TL7RmB5eW5b31zkjbm/Op1xPytG1rBb7jBZNDAgj238fdL/3BtnfZ85Tv9fJ9Hs3y9lkSRbl96k6lHpYfh0q/tX37aTl516Uj2kyT0z3Z+jNGUYPjZRmRCMaWTry+uL4m791XXTt2WtT3MUJ00jqjoA1g1vP3XD1rqu++lcbT7z2l8QSYC76wfmYnPRqw6h8Y8xrnlEeh56yUvO9sn7N4wWuGTUnRzWyRkCWw09pLGQ8q2wQte91RjazWpajZJVYCqCfUi04+b17P9/64oe/HL+8IX5V9LYkzUVSkiJJaQfitnM3/PaOz2x4pNQXKAY8MJvh0ItLWzMc5spb2a9Ft1SiOTIqlkwWo/TFcmwCeGWV7s05iqUvFRxLaY5WHn1lbSQNmkfVDsQdneuvfHr0a8QSkMGS/M3W5zeebZ7HiBqZK7O5kgSzkIExaWHOUhH2y0OqlT+Lu5RvzCqWrmiER1w+b5pRJCEjafngoXXxKhp2t7YQG1sTVz3VuPf7dZjDAuTF59/St5ZkfZnZkr5xK2UI5rjD8nt2lz+bNNQuuc2VPdwWV9oRjJVY+tX1LmIpbSBFjr786vnlAyuRFET/F6afqdYR4fTll4xsJ5aATHyLpWg77i/RYa2lChwSWijZGVgq7h7yfL8vy22s9JykXqU+1PN33TlL+cWSTiBFjr30auvjbiSFq/fXKqUolsLwrkvXNYklIBsVS0UfgtkfW6OmTFQslXlkaV4GapnMyUNxPo4u7Y0tj1ArpZ8T8z0ZS5cHdmNJd9WEYy/tay0fODiyMpIU3V8+QGxkKd3zhtFHFEtPEktAJmr+RxFzbtRv3pMlnsOhYtOntZ50RbH0lZKNjh2WIzY3exKqizI4p6q24nZalZg83D0Md8JOLOmOIkWOvbiv9fHbh0ZWeijs3j8QsdpKEUsykOL//i1iCchMXbn9Zkdv+MtyLtJERX7zViNLvh8SSrIgX49t/m5iX+ryOpsKilUVSBNVusCtidIsOJnGd394aOSNq65970wYXKN7X9PdcOyFfa2P3zk4EgYrPRMGagm1oPu/7sPKz638e7BmibWk1yAIgqfOnW/f3fnhd6rzQlWL7gKAThdKK8iE5sU7Dzv8TXVKTqi2fbHaRflmMqc5d2NSY0XlpYJHp8ZkdNpYp0jIfebqIq/KhJwrZuv1f8hhEKuVzadzXKdqWS5dMe/wZ5Xuz9AF1/OjKhVKQjOWsn7px194pfXxO4dGOuo/GMRSmv1PLAHWjckf0NMyVkwWGNwr30x21uEU6R7TsQ+daFqO7bMiRynUpWemDRbYXIxtf1Gv+6T8/p2SfzYNp/gK9HX8Pk6lcqEkUsSSjS/5+POvtJbfPjiigihUo0QpY6kT6i3eTywBuVO/2Sb9hrsgR794Q7lAjSAm7bc9HoyIJZmKXd6jn6XYa+/jPJ2x2OjksGsVqpEi5yMzZVXJUBIDYsnWl3rs+VdaJ99aiaSVABJasRTKSUz9DsMN0r1LILZ/2urcQywBAOBGZVeCjk/wNpmgPcjxn73cOvnmgRF12v/KpO2V/wvUc8gnC8ILn1tZljsUYaej9XwiPic8FJsvGWk8wQRvAADcqOyIkqJGlk539Cd4x0V76cO9L7dOvnVgdeL22tEiMXBkKRQrQ0JhI/p8+s7p9/IwsgQAgBuVDyWRMZbU3vlwz0urh9u6/z1lLEX/7DRWAkloBJIYcqiQWAIAIH+1CCVhEEvxvRJF0ifdw20ykIbEUnfUqNkQnYbQGj1afe6ULwmxBABAvmoTSiJlLPXujRO7X5JzksTFgbQmlgLRGWmsfGSYQaT7chBLAADkp1ahJBJiqd9eOPHcixePJIneWIrF0Ugj1ZpIg5jeVd5te6tNLAEAYFvtQknEYulUwsjSiZ++2P7kzXeaQqwdPeqsa4r2Jc1uHCkFRpJCLAEAYFktQyly018vNC+b/ML7/WLpxE9faJ9640BTqLWQRLASRlEgrWtcNCk76/4zuXvCXYglAAAsqm0oiQGxdOInL7RPvf5Os7t69rqmaF060o2k3jPWiggkkRxJCrEEAIAltQ6lyE1/s9C8bP1KLH3078+3T759qNm6bES0Lx1ZOaW/R1GBJNJFkkIsAQBgQe1DSciRpRMnl149dujd3wub/U9Zs7GfchxF6odYAgAgI0JJ+szXHml0xq/c2Q7EHfH/XmQgCfNIUtu9vd0JiSUAAAwRSjG/+YePNMLxK3e0hbjT1n5xHUl9tptYAgDAEKHUI4ql9vWf3dER4s4sj1PgKFI/xBIAAAYa7LSLnfzZn3dG3vv1poYQu0zuH7WKZ5EU2dxsBE807v1+hjXDAQCoH0aUBohGllrXX/lUKMLpNLfPuhtzCqRejCwBAKCBEaUBopGlc632XYEIdiTdLusIknAXSYKRJQAA9BBKCaKRl3Ot9reCIHi691a2AslhJKltJpYAAEiJQ28pRFFx6brm9jAM77Kxu7I8hOnr1Xu3IOAwHAAAwzCilEJ3ZOl8e3M0xyfrY/kQSfK/MbIEAMAQjChpiKLikpHGE1Fk6N7Xl0DqxcgSAACDMaKkIYqJT1ude6K4SHuvLPOQRM6RJBhZAgAgESNKBtKMLGXdq1leF8O7PtkJw28zsgQAwAWEkqFBsWRjb+Y9irTmfnKrAxEQSwAAxBBKGfTGUtlGkcI+W0wsAQBwAaGUURRLI83GE9FijlkeyYdIUoglAABWEEoWZImlAuYiJUaSQiwBAEAoWaMbS1n3e56RpBBLAIC6I5QsShNLZQiknud6UghBLAEAaol1lCyKYqLV7twzaAXvEkZS5G4hxI9YZwkAUDtCiP8H5/u1dCM1SvoAAAAASUVORK5CYII=">
</svg>
''';

    expect(
        () => encodeSvg(
            xml: svgInlineImage, debugName: 'test.svg', warningsAsErrors: true),
        throwsA(isA<UnimplementedError>()));
  });

  test('encodeSvg encodes stroke shaders', () async {
    const String svg = '''
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 120 120">
  <defs>
    <linearGradient id="j" x1="69" y1="59" x2="36" y2="84" gradientUnits="userSpaceOnUse">
      <stop offset="0" stop-color="#ffffff" />
      <stop offset="1" stop-color="#000000" />
    </linearGradient>
  </defs>
  <g>
    <path d="M34 76h23" fill="none" stroke-linecap="round" stroke-linejoin="round" stroke-width="8" stroke="url(#j)" />
  </g>
</svg>
''';

    final Uint8List bytes = await encodeSvg(xml: svg, debugName: 'test');
    const VectorGraphicsCodec codec = VectorGraphicsCodec();
    final TestListener listener = TestListener();
    codec.decode(bytes.buffer.asByteData(), listener);
    expect(listener.commands, <Object>[
      const OnSize(120, 120),
      OnLinearGradient(
        id: 0,
        fromX: 69,
        fromY: 59,
        toX: 36,
        toY: 84,
        colors: Int32List.fromList(<int>[0xffffffff, 0xff000000]),
        offsets: Float32List.fromList(<double>[0, 1]),
        tileMode: 0,
      ),
      OnPaintObject(
        color: 0xffffffff,
        strokeCap: 1,
        strokeJoin: 1,
        blendMode: BlendMode.srcOver.index,
        strokeMiterLimit: 4.0,
        strokeWidth: 8,
        paintStyle: 1,
        id: 0,
        shaderId: 0,
      ),
      const OnPathStart(0, 0),
      const OnPathMoveTo(34, 76),
      const OnPathLineTo(57, 76),
      const OnPathFinished(),
      const OnDrawPath(0, 0),
    ]);
  });

  test('Encodes nested tspan for text', () async {
    const String svg = '''
<svg viewBox="0 0 1000 300" xmlns="http://www.w3.org/2000/svg" version="1.1">

  <text x="100" y="50"
      font-family="Roboto" font-size="55" font-weight="normal" fill="blue" >
    Plain text Roboto</text>
  <text x="100" y="100"
      font-family="Verdana" font-size="55" font-weight="normal" fill="blue" >
    Plain text Verdana</text>

  <text x="100" y="150"
      font-family="Verdana" font-size="55" font-weight="bold" fill="blue" >
    Bold text Verdana</text>

  <text x="150" y="215"
      font-family="Roboto" font-size="55" fill="green" >
    <tspan stroke="red" font-weight="900" >Stroked bold line</tspan>
    <tspan y="50">Line 3</tspan>
  </text>
</svg>
''';

    final Uint8List bytes = await encodeSvg(xml: svg, debugName: 'test');
    const VectorGraphicsCodec codec = VectorGraphicsCodec();
    final TestListener listener = TestListener();
    codec.decode(bytes.buffer.asByteData(), listener);
    expect(listener.commands, <Object>[
      const OnSize(1000, 300),
      OnPaintObject(
        color: 4278190335,
        strokeCap: null,
        strokeJoin: null,
        blendMode: BlendMode.srcOver.index,
        strokeMiterLimit: null,
        strokeWidth: null,
        paintStyle: 0,
        id: 0,
        shaderId: null,
      ),
      OnPaintObject(
        color: 4278222848,
        strokeCap: null,
        strokeJoin: null,
        blendMode: BlendMode.srcOver.index,
        strokeMiterLimit: null,
        strokeWidth: null,
        paintStyle: 0,
        id: 1,
        shaderId: null,
      ),
      OnPaintObject(
        color: 4294901760,
        strokeCap: 0,
        strokeJoin: 0,
        blendMode: BlendMode.srcOver.index,
        strokeMiterLimit: 4.0,
        strokeWidth: 1.0,
        paintStyle: 1,
        id: 2,
        shaderId: null,
      ),
      OnPaintObject(
        color: 4278222848,
        strokeCap: null,
        strokeJoin: null,
        blendMode: BlendMode.srcOver.index,
        strokeMiterLimit: null,
        strokeWidth: null,
        paintStyle: 0,
        id: 3,
        shaderId: null,
      ),
      const OnTextConfig(
          'Plain text Roboto', 100, 50, 55, 'Roboto', 3, null, 0),
      const OnTextConfig(
          'Plain text Verdana', 100, 100, 55, 'Verdana', 3, null, 1),
      const OnTextConfig(
          'Bold text Verdana', 100, 150, 55, 'Verdana', 6, null, 2),
      const OnTextConfig(
          'Stroked bold line', 150, 215, 55, 'Roboto', 8, null, 3),
      const OnTextConfig('Line 3', 150, 50, 55, 'Roboto', 3, null, 4),
      const OnDrawText(0, 0),
      const OnDrawText(1, 0),
      const OnDrawText(2, 0),
      const OnDrawText(3, 1),
      const OnDrawText(3, 2),
      const OnDrawText(4, 3),
    ]);
  });
}

class TestListener extends VectorGraphicsCodecListener {
  final List<Object> commands = <Object>[];

  @override
  void onDrawPath(int pathId, int? paintId) {
    commands.add(OnDrawPath(pathId, paintId));
  }

  @override
  void onDrawVertices(Float32List vertices, Uint16List? indices, int? paintId) {
    commands.add(OnDrawVertices(vertices, indices, paintId));
  }

  @override
  void onPaintObject({
    required int color,
    required int? strokeCap,
    required int? strokeJoin,
    required int blendMode,
    required double? strokeMiterLimit,
    required double? strokeWidth,
    required int paintStyle,
    required int id,
    required int? shaderId,
  }) {
    commands.add(
      OnPaintObject(
        color: color,
        strokeCap: strokeCap,
        strokeJoin: strokeJoin,
        blendMode: blendMode,
        strokeMiterLimit: strokeMiterLimit,
        strokeWidth: strokeWidth,
        paintStyle: paintStyle,
        id: id,
        shaderId: shaderId,
      ),
    );
  }

  @override
  void onPathClose() {
    commands.add(const OnPathClose());
  }

  @override
  void onPathCubicTo(
      double x1, double y1, double x2, double y2, double x3, double y3) {
    commands.add(OnPathCubicTo(x1, y1, x2, y2, x3, y3));
  }

  @override
  void onPathFinished() {
    commands.add(const OnPathFinished());
  }

  @override
  void onPathLineTo(double x, double y) {
    commands.add(OnPathLineTo(x, y));
  }

  @override
  void onPathMoveTo(double x, double y) {
    commands.add(OnPathMoveTo(x, y));
  }

  @override
  void onPathStart(int id, int fillType) {
    commands.add(OnPathStart(id, fillType));
  }

  @override
  void onRestoreLayer() {
    commands.add(const OnRestoreLayer());
  }

  @override
  void onMask() {
    commands.add(const OnMask());
  }

  @override
  void onSaveLayer(int id) {
    commands.add(OnSaveLayer(id));
  }

  @override
  void onClipPath(int pathId) {
    commands.add(OnClipPath(pathId));
  }

  @override
  void onRadialGradient(
    double centerX,
    double centerY,
    double radius,
    double? focalX,
    double? focalY,
    Int32List colors,
    Float32List? offsets,
    Float64List? transform,
    int tileMode,
    int id,
  ) {
    commands.add(
      OnRadialGradient(
        centerX: centerX,
        centerY: centerY,
        radius: radius,
        focalX: focalX,
        focalY: focalY,
        colors: colors,
        offsets: offsets,
        transform: transform,
        tileMode: tileMode,
        id: id,
      ),
    );
  }

  @override
  void onLinearGradient(
    double fromX,
    double fromY,
    double toX,
    double toY,
    Int32List colors,
    Float32List? offsets,
    int tileMode,
    int id,
  ) {
    commands.add(OnLinearGradient(
      fromX: fromX,
      fromY: fromY,
      toX: toX,
      toY: toY,
      colors: colors,
      offsets: offsets,
      tileMode: tileMode,
      id: id,
    ));
  }

  @override
  void onSize(double width, double height) {
    commands.add(OnSize(width, height));
  }

  @override
  void onTextConfig(
    String text,
    String? fontFamily,
    double dx,
    double dy,
    int fontWeight,
    double fontSize,
    Float64List? transform,
    int id,
  ) {
    commands.add(OnTextConfig(
      text,
      dx,
      dy,
      fontSize,
      fontFamily,
      fontWeight,
      transform,
      id,
    ));
  }

  @override
  void onDrawText(int textId, int paintId) {
    commands.add(OnDrawText(textId, paintId));
  }

  @override
  void onDrawImage(int imageId, double x, double y, int width, int height) {
    commands.add(OnDrawImage(imageId, x, y, width, height));
  }

  @override
  void onImage(int imageId, int format, Uint8List data) {
    commands.add(OnImage(imageId, format, data));
  }
}

class OnMask {
  const OnMask();
}

class OnLinearGradient {
  const OnLinearGradient({
    required this.fromX,
    required this.fromY,
    required this.toX,
    required this.toY,
    required this.colors,
    required this.offsets,
    required this.tileMode,
    required this.id,
  });

  final double fromX;
  final double fromY;
  final double toX;
  final double toY;
  final Int32List colors;
  final Float32List? offsets;
  final int tileMode;
  final int id;

  @override
  int get hashCode => Object.hash(
        fromX,
        fromY,
        toX,
        toY,
        Object.hashAll(colors),
        Object.hashAll(offsets ?? <double>[]),
        tileMode,
        id,
      );

  @override
  bool operator ==(Object other) {
    return other is OnLinearGradient &&
        other.fromX == fromX &&
        other.fromY == fromY &&
        other.toX == toX &&
        other.toY == toY &&
        _listEquals(other.colors, colors) &&
        _listEquals(other.offsets, offsets) &&
        other.tileMode == tileMode &&
        other.id == id;
  }

  @override
  String toString() {
    return 'OnLinearGradient('
        'fromX: $fromX, '
        'toX: $toX, '
        'fromY: $fromY, '
        'toY: $toY, '
        'colors: Int32List.fromList($colors), '
        'offsets: Float32List.fromList($offsets), '
        'tileMode: $tileMode, '
        'id: $id)';
  }
}

class OnRadialGradient {
  const OnRadialGradient({
    required this.centerX,
    required this.centerY,
    required this.radius,
    required this.focalX,
    required this.focalY,
    required this.colors,
    required this.offsets,
    required this.transform,
    required this.tileMode,
    required this.id,
  });

  final double centerX;
  final double centerY;
  final double radius;
  final double? focalX;
  final double? focalY;
  final Int32List colors;
  final Float32List? offsets;
  final Float64List? transform;
  final int tileMode;
  final int id;

  @override
  int get hashCode => Object.hash(
        centerX,
        centerY,
        radius,
        focalX,
        focalY,
        Object.hashAll(colors),
        Object.hashAll(offsets ?? <double>[]),
        Object.hashAll(transform ?? <double>[]),
        tileMode,
        id,
      );

  @override
  bool operator ==(Object other) {
    return other is OnRadialGradient &&
        other.centerX == centerX &&
        other.centerY == centerY &&
        other.radius == radius &&
        other.focalX == focalX &&
        other.focalX == focalY &&
        _listEquals(other.colors, colors) &&
        _listEquals(other.offsets, offsets) &&
        _listEquals(other.transform, transform) &&
        other.tileMode == tileMode &&
        other.id == id;
  }
}

class OnSaveLayer {
  const OnSaveLayer(this.id);

  final int id;

  @override
  int get hashCode => id.hashCode;

  @override
  bool operator ==(Object other) => other is OnSaveLayer && other.id == id;
}

class OnClipPath {
  const OnClipPath(this.id);

  final int id;

  @override
  int get hashCode => id.hashCode;

  @override
  bool operator ==(Object other) => other is OnClipPath && other.id == id;
}

class OnRestoreLayer {
  const OnRestoreLayer();
}

class OnDrawPath {
  const OnDrawPath(this.pathId, this.paintId);

  final int pathId;
  final int? paintId;

  @override
  int get hashCode => Object.hash(pathId, paintId);

  @override
  bool operator ==(Object other) =>
      other is OnDrawPath && other.pathId == pathId && other.paintId == paintId;

  @override
  String toString() => 'OnDrawPath($pathId, $paintId)';
}

class OnDrawVertices {
  const OnDrawVertices(this.vertices, this.indices, this.paintId);

  final List<double> vertices;
  final List<int>? indices;
  final int? paintId;

  @override
  int get hashCode => Object.hash(
      Object.hashAll(vertices), Object.hashAll(indices ?? <int>[]), paintId);

  @override
  bool operator ==(Object other) =>
      other is OnDrawVertices &&
      _listEquals(vertices, other.vertices) &&
      _listEquals(indices, other.indices) &&
      other.paintId == paintId;

  @override
  String toString() => 'OnDrawVertices($vertices, $indices, $paintId)';
}

class OnPaintObject {
  const OnPaintObject({
    required this.color,
    required this.strokeCap,
    required this.strokeJoin,
    required this.blendMode,
    required this.strokeMiterLimit,
    required this.strokeWidth,
    required this.paintStyle,
    required this.id,
    required this.shaderId,
  });

  final int color;
  final int? strokeCap;
  final int? strokeJoin;
  final int blendMode;
  final double? strokeMiterLimit;
  final double? strokeWidth;
  final int paintStyle;
  final int id;
  final int? shaderId;

  @override
  int get hashCode => Object.hash(color, strokeCap, strokeJoin, blendMode,
      strokeMiterLimit, strokeWidth, paintStyle, id, shaderId);

  @override
  bool operator ==(Object other) =>
      other is OnPaintObject &&
      other.color == color &&
      other.strokeCap == strokeCap &&
      other.strokeJoin == strokeJoin &&
      other.blendMode == blendMode &&
      other.strokeMiterLimit == strokeMiterLimit &&
      other.strokeWidth == strokeWidth &&
      other.paintStyle == paintStyle &&
      other.id == id &&
      other.shaderId == shaderId;

  @override
  String toString() =>
      'OnPaintObject(color: $color, strokeCap: $strokeCap, strokeJoin: $strokeJoin, '
      'blendMode: $blendMode, strokeMiterLimit: $strokeMiterLimit, strokeWidth: $strokeWidth, '
      'paintStyle: $paintStyle, id: $id, shaderId: $shaderId)';
}

class OnPathClose {
  const OnPathClose();

  @override
  int get hashCode => 44221;

  @override
  bool operator ==(Object other) => other is OnPathClose;

  @override
  String toString() => 'OnPathClose';
}

class OnPathCubicTo {
  const OnPathCubicTo(this.x1, this.y1, this.x2, this.y2, this.x3, this.y3);

  final double x1;
  final double x2;
  final double x3;
  final double y1;
  final double y2;
  final double y3;

  @override
  int get hashCode => Object.hash(x1, y1, x2, y2, x3, y3);

  @override
  bool operator ==(Object other) =>
      other is OnPathCubicTo &&
      other.x1 == x1 &&
      other.y1 == y1 &&
      other.x2 == x2 &&
      other.y2 == y2 &&
      other.x3 == x3 &&
      other.y3 == y3;

  @override
  String toString() => 'OnPathCubicTo($x1, $y1, $x2, $y2, $x3, $y3)';
}

class OnPathFinished {
  const OnPathFinished();

  @override
  int get hashCode => 1223;

  @override
  bool operator ==(Object other) => other is OnPathFinished;

  @override
  String toString() => 'OnPathFinished';
}

class OnPathLineTo {
  const OnPathLineTo(this.x, this.y);

  final double x;
  final double y;

  @override
  int get hashCode => Object.hash(x, y);

  @override
  bool operator ==(Object other) =>
      other is OnPathLineTo && other.x == x && other.y == y;

  @override
  String toString() => 'OnPathLineTo($x, $y)';
}

class OnPathMoveTo {
  const OnPathMoveTo(this.x, this.y);

  final double x;
  final double y;

  @override
  int get hashCode => Object.hash(x, y);

  @override
  bool operator ==(Object other) =>
      other is OnPathMoveTo && other.x == x && other.y == y;

  @override
  String toString() => 'OnPathMoveTo($x, $y)';
}

class OnPathStart {
  const OnPathStart(this.id, this.fillType);

  final int id;
  final int fillType;

  @override
  int get hashCode => Object.hash(id, fillType);

  @override
  bool operator ==(Object other) =>
      other is OnPathStart && other.id == id && other.fillType == fillType;

  @override
  String toString() => 'OnPathStart($id, $fillType)';
}

class OnSize {
  const OnSize(this.width, this.height);

  final double width;
  final double height;

  @override
  int get hashCode => Object.hash(width, height);

  @override
  bool operator ==(Object other) =>
      other is OnSize && other.width == width && other.height == height;

  @override
  String toString() => 'OnSize($width, $height)';
}

class OnTextConfig {
  const OnTextConfig(
    this.text,
    this.x,
    this.y,
    this.fontSize,
    this.fontFamily,
    this.fontWeight,
    this.transform,
    this.id,
  );

  final String text;
  final double x;
  final double y;
  final double fontSize;
  final String? fontFamily;
  final int fontWeight;
  final int id;
  final Float64List? transform;

  @override
  int get hashCode => Object.hash(text, x, y, fontSize, fontFamily, fontWeight,
      Object.hashAll(transform ?? <double>[]), id);

  @override
  bool operator ==(Object other) =>
      other is OnTextConfig &&
      other.text == text &&
      other.x == x &&
      other.y == y &&
      other.fontSize == fontSize &&
      other.fontFamily == fontFamily &&
      other.fontWeight == fontWeight &&
      _listEquals(other.transform, transform) &&
      other.id == id;

  @override
  String toString() =>
      'OnTextConfig($text, $x, $y, $fontSize, $fontFamily, $fontWeight, $transform, $id)';
}

class OnDrawText {
  const OnDrawText(this.textId, this.paintId);

  final int textId;
  final int paintId;

  @override
  int get hashCode => Object.hash(textId, paintId);

  @override
  bool operator ==(Object other) =>
      other is OnDrawText && other.textId == textId && other.paintId == paintId;

  @override
  String toString() => 'OnDrawText($textId, $paintId)';
}

class OnImage {
  const OnImage(this.id, this.format, this.data);

  final int id;
  final int format;
  final List<int> data;

  @override
  int get hashCode => Object.hash(id, format, data);

  @override
  bool operator ==(Object other) =>
      other is OnImage &&
      other.id == id &&
      other.format == format &&
      _listEquals(other.data, data);

  @override
  String toString() => 'OnImage($id, $format, data:${data.length} bytes)';
}

class OnDrawImage {
  const OnDrawImage(this.id, this.x, this.y, this.width, this.height);

  final int id;
  final double x;
  final double y;
  final int width;
  final int height;

  @override
  int get hashCode => Object.hash(id, x, y, width, height);

  @override
  bool operator ==(Object other) {
    return other is OnDrawImage &&
        other.id == id &&
        other.x == x &&
        other.y == y &&
        other.width == width &&
        other.height == height;
  }

  @override
  String toString() => 'OnDrawImage($id, $x, $y, $width, $height)';
}

bool _listEquals<E>(List<E>? left, List<E>? right) {
  if (left == null && right == null) {
    return true;
  }
  if (left == null || right == null) {
    return false;
  }
  if (left.length != right.length) {
    return false;
  }
  for (int i = 0; i < left.length; i++) {
    if (left[i] != right[i]) {
      return false;
    }
  }
  return true;
}
