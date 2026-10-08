# BigDataTrino

Лабораторная работа №4: ETL на Trino для данных зоомагазина. Docker Compose поднимает PostgreSQL, ClickHouse и Trino; ETL загружает исходные CSV в две базы, строит звезду в ClickHouse и рассчитывает шесть витрин.

## Запуск

Нужны Docker и Docker Compose. Запускайте из корня репозитория:

```bash
docker compose up -d --build
docker compose logs -f etl
```

Загрузка завершена, когда в логах появится `ETL completed`. Первый запуск может занять несколько минут: Trino ожидает готовности обеих баз, затем выполняет SQL из `sql/`.

Первые пять файлов (`MOCK_DATA.csv`, `(1)`–`(4)`) загружаются в ClickHouse, следующие пять (`(5)`–`(9)`) — в PostgreSQL.

| Сервис | Подключение с хоста |
| --- | --- |
| Trino UI | `http://localhost:28080` |
| PostgreSQL | `localhost:25432`, база/пользователь/пароль `sales` |
| ClickHouse HTTP | `localhost:28123`, база `raw`, пользователь/пароль `sales` |

Trino использует каталоги `clickhouse` и `postgres`. Исходные таблицы — `clickhouse.raw.mock_data` и `postgres.public.mock_data`.

## ETL и модель

`app/run.py` CSV-парсером читает десять файлов (включая многострочные поля в кавычках), проверяет заголовки и ровно 1 000 записей в каждом, добавляет `source_file`, `source_row` и уникальный `source_row_id`, затем загружает 5 000 строк в каждую БД. Такой ключ нужен, поскольку `id` повторяется между файлами.

`sql/01_star.sql` выполняется Trino и создаёт схему `clickhouse.sales`: промежуточную таблицу `staging_sales`, измерения `dim_customer`, `dim_seller`, `dim_product`, `dim_store`, `dim_supplier`, `dim_date` и факт `fact_sales`. В наборе нет стабильного SKU, поэтому снимок атрибутов товара привязан к исходной строке, а в витринах товары группируются по названию и категории.

`sql/02_marts.sql` создаёт таблицы:

| Таблица | Содержание |
| --- | --- |
| `mart_products` | Продажи и рейтинг товара, рейтинг продаж, выручка категории |
| `mart_customers` | Покупки и средний чек клиента, ранг по выручке, число клиентов в стране |
| `mart_time` | Месячные и годовые итоги, средние размеры заказа, изменение к предыдущему периоду |
| `mart_stores` | Выручка и средний чек магазина, ранг, итоги по городу и стране |
| `mart_suppliers` | Выручка, средняя цена товара, ранг и итоги по стране |
| `mart_quality` | Рейтинг, отзывы, продажи, ранги и корреляция рейтинга с объёмом продаж |

Топы выбираются по `sales_rank`, `spending_rank` или `revenue_rank`; соответствующие оконные итоги доступны в каждой строке группы.

## Проверка

Выполнить сверки Trino:

```bash
docker compose exec -T trino trino --file /dev/stdin < sql/03_checks.sql
```

Ожидаемые контрольные значения: 5 000 строк в каждом источнике, 10 000 фактов, 10 000 уникальных `source_row_id`, сумма `sale_quantity` и выручка `2529852.12`. Для DBeaver подключитесь к ClickHouse (`localhost:28123`, HTTP, база `sales`, пользователь/пароль `sales`) и проверьте, например:

```sql
SELECT * FROM sales.mart_products ORDER BY sales_rank;
SELECT * FROM sales.mart_customers ORDER BY spending_rank;
SELECT * FROM sales.mart_time ORDER BY period_type, period_start;
SELECT * FROM sales.mart_stores ORDER BY revenue_rank;
SELECT * FROM sales.mart_suppliers ORDER BY revenue_rank;
SELECT * FROM sales.mart_quality ORDER BY rating_rank_desc;
```

Повторно выполнить весь ETL без накопления строк можно командой `docker compose run --rm etl`: скрипт заново загружает исходные таблицы и пересоздаёт модель и витрины. Остановить сервисы: `docker compose down`. Для полного сброса вместе с данными: `docker compose down -v`.
