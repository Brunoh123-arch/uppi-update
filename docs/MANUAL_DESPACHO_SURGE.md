# 📖 Manual de Configuração: Despacho Inteligente e Preço Dinâmico (Surge) por Cerca Virtual

Este manual explica como operar, testar e configurar o novo motor de despacho e o sistema de cerca virtual de preço dinâmico (Surge Pricing) no Uppi.

---

## 🧠 1. Despacho Inteligente (Matching Engine)

O novo motor de despacho não usa apenas a distância linear para escolher o motorista. Ele executa uma função no banco de dados (`get_nearby_drivers_scored`) que calcula uma **nota de relevância (score)** para cada motorista online em um raio de até 5 km.

### Como a nota (Score) do motorista é calculada:
A fórmula pondera três fatores cruciais:
$$\text{Score} = (\text{Proximidade} \times 40\%) + (\text{Nota/Rating} \times 40\%) + (\text{Bônus de Disponibilidade} \times 20\%)$$

1. **Proximidade (40% de peso)**: Mede a distância real via coordenadas geográficas. Motoristas mais próximos ganham pontuação maior.
2. **Avaliação/Rating (40% de peso)**: Utiliza a nota média do motorista (de 0.0 a 5.0) guardada em seu perfil. Motoristas 5 estrelas ganham mais pontos.
3. **Bônus de Disponibilidade (20% de peso)**: Motoristas ativos e livres ganham um bônus para evitar que fiquem muito tempo sem corridas.

---

## ⚡ 2. Preço Dinâmico (Surge Pricing) por Cerca Virtual

O valor da corrida pode subir automaticamente em áreas de alta demanda de duas maneiras:
1. **Cálculo de Demanda Automático**: O sistema compara corridas ativas vs. motoristas online na região.
2. **Cerca Virtual Manual (Surge Zones)**: O administrador define áreas específicas no mapa (ex: Shows, Aeroporto, Centro) onde o multiplicador é fixado.

### ⚙️ Como Ativar o Preço Dinâmico Geral
Certifique-se de que as seguintes chaves estão configuradas na tabela `app_settings` no seu banco de dados:

* `surge_enabled`: `'true'` (para ativar o sistema)
* `surge_max_multiplier`: `'2.5'` (limite máximo que a tarifa pode subir, ex: 2.5x)
* `global_surge_multiplier`: `'1.0'` (se maior que 1.0, força esse multiplicador em toda a cidade)

---

## 🗺️ 3. Como Criar uma Cerca Virtual (Surge Zone) no Banco

Para aplicar o multiplicador em uma área desenhada no mapa, você deve inserir um registro na tabela `surge_zones`. A fronteira da área é definida usando formato **WKT (Well-Known Text)** de polígonos PostGIS:

### Exemplo de Comando SQL para criar uma Cerca Virtual:
Execute este comando no console SQL do seu Supabase para criar uma zona no Aeroporto com multiplicador de **1.8x**:

```sql
INSERT INTO public.surge_zones (name, boundary, multiplier, is_active, expires_at)
VALUES (
  'ZONA AEROPORTO SHOW',
  -- Defina as coordenadas dos cantos da cerca fechando o polígono (longitude latitude)
  -- Importante: o último ponto deve ser exatamente igual ao primeiro ponto para fechar a área!
  ST_GeographyFromText('POLYGON((-46.6625 -23.6262, -46.6525 -23.6262, -46.6525 -23.6362, -46.6625 -23.6362, -46.6625 -23.6262))'),
  1.80, -- Multiplicador de 1.8x na tarifa
  true, -- Cerca ativa
  NOW() + INTERVAL '4 hours' -- Expira automaticamente em 4 horas
);
```

### Como o sistema valida o preço:
Toda vez que uma corrida é solicitada:
1. O app chama a Edge Function `/calculate-surge` informando a latitude e longitude do ponto de partida.
2. O Supabase executa a função espacial `get_matching_surge_zone` e verifica se o ponto de partida do passageiro está contido (`ST_Contains`) em algum polígono ativo.
3. Se o passageiro estiver dentro da cerca, a tarifa dinâmica é aplicada imediatamente.
