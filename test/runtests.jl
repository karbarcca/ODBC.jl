using Test, ODBC, DBInterface, Tables, Dates, DecFP, MariaDB_Connector_ODBC_jll, MariaDB_Connector_C_jll

tracefile = abspath(joinpath(@__DIR__, "odbc.log"))
ODBC.setdebug(true, tracefile)
@show ODBC.drivers()
@show ODBC.dsns()
ODBC.setdebug(false)
@test filesize(tracefile) > 0
rm(tracefile)

PLUGIN_DIR = joinpath(MariaDB_Connector_C_jll.artifact_dir, "lib", "mariadb", "plugin")
if Sys.islinux()
    if Int == Int32
        libpath = joinpath(ENV["TRAVIS_BUILD_DIR"], "mariadb32/lib/libmaodbc.so")
    else
        libpath = joinpath(ENV["TRAVIS_BUILD_DIR"], "mariadb64/lib/libmaodbc.so")
    end
elseif Sys.iswindows()
    if Int == Int32
        libpath = joinpath(ENV["TRAVIS_BUILD_DIR"], "mariadb-connector-odbc-3.1.7-win32", "maodbc.dll")
    else
        @show readdir(joinpath(ENV["TRAVIS_BUILD_DIR"], "mariadb-connector-odbc-3.1.7-win64", "SourceDir"))
        libpath = joinpath(ENV["TRAVIS_BUILD_DIR"], "mariadb-connector-odbc-3.1.7-win64", "SourceDir", "maodbc.dll")
    end
else
    libpath = MariaDB_Connector_ODBC_jll.libmaodbc_path
end
ODBC.adddriver("ODBC_Test_MariaDB", libpath)
ODBC.adddsn("ODBC_Test_DSN_MariaDB", "ODBC_Test_MariaDB"; SERVER="localhost", PLUGIN_DIR=PLUGIN_DIR, Option=67108864, CHARSET="utf8mb4")

conn = DBInterface.connect(ODBC.Connection, "ODBC_Test_DSN_MariaDB", "root")
DBInterface.close!(conn)
conn = DBInterface.connect(ODBC.Connection, "ODBC_Test_DSN_MariaDB", "root")

DBInterface.execute(conn, "DROP DATABASE if exists mysqltest")
DBInterface.execute(conn, "CREATE DATABASE mysqltest")
DBInterface.execute(conn, "use mysqltest")
DBInterface.execute(conn, """CREATE TABLE Employee
                 (
                     ID INT NOT NULL AUTO_INCREMENT,
                     OfficeNo TINYINT,
                     DeptNo SMALLINT,
                     EmpNo BIGINT UNSIGNED,
                     Wage FLOAT(7,2),
                     Salary DOUBLE,
                     Rate DECIMAL(5, 3),
                     LunchTime TIME,
                     JoinDate DATE,
                     LastLogin DATETIME,
                     LastLogin2 TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
                     Initial CHAR(1),
                     Name VARCHAR(255) CHARACTER SET utf8mb4,
                     Photo BLOB,
                     JobType ENUM('HR', 'Management', 'Accounts'),
                     Senior BIT(1),
                     PRIMARY KEY (ID)
                 );""")

DBInterface.execute(conn, """INSERT INTO Employee (OfficeNo, DeptNo, EmpNo, Wage, Salary, Rate, LunchTime, JoinDate, LastLogin, LastLogin2, Initial, Name, Photo, JobType, Senior)
                 VALUES
                 (1, 2, 1301, 3.14, 10000.50, 1.001, '12:00:00', '2015-8-3', '2015-9-5 12:31:30', '2015-9-5 12:31:30', 'A', 'John', 'abc', 'HR', b'1'),
                 (1, 2, 1422, 3.14, 20000.25, 2.002, '13:00:00', '2015-8-4', '2015-10-12 13:12:14', '2015-10-12 13:12:14', 'B', 'Tom', 'def', 'HR', b'1'),
                 (1, 2, 1567, 3.14, 30000.00, 3.003, '12:30:00', '2015-6-2', '2015-9-5 10:05:10', '2015-9-5 10:05:10', 'C', 'Jim', 'ghi', 'Management', b'0'),
                 (1, 2, 3200, 3.14, 15000.50, 2.5, '12:30:00', '2015-7-25', '2015-10-10 12:12:25', '2015-10-10 12:12:25', 'D', '望研測来白制父委供情治当認米注。規', 'jkl', 'Accounts', b'1');
              """)

expected = (
  ID         = Union{Missing, Int32}[1, 2, 3, 4],
  OfficeNo   = Union{Missing, Int8}[1, 1, 1, 1],
  DeptNo     = Union{Missing, Int16}[2, 2, 2, 2],
  EmpNo      = Union{Missing, Int64}[1301, 1422, 1567, 3200],
  Wage       = Union{Missing, Float32}[3.14, 3.14, 3.14, 3.14],
  Salary     = Union{Missing, Float64}[10000.5, 20000.25, 30000.0, 15000.5],
  Rate       = Union{Missing, Dec64}[d64"1.001", d64"2.002", d64"3.003", d64"2.5"],
  LunchTime  = Union{Missing, Dates.Time}[Dates.Time(12,00,00), Dates.Time(13,00,00), Dates.Time(12,30,00), Dates.Time(12,30,00)],
  JoinDate   = Union{Missing, Dates.Date}[Date("2015-08-03"), Date("2015-08-04"), Date("2015-06-02"), Date("2015-07-25")],
  LastLogin  = Union{Missing, Dates.DateTime}[DateTime("2015-09-05T12:31:30"), DateTime("2015-10-12T13:12:14"), DateTime("2015-09-05T10:05:10"), DateTime("2015-10-10T12:12:25")],
  LastLogin2 = Union{Missing, Dates.DateTime}[DateTime("2015-09-05T12:31:30"), DateTime("2015-10-12T13:12:14"), DateTime("2015-09-05T10:05:10"), DateTime("2015-10-10T12:12:25")],
  Initial    = Union{Missing, String}["A", "B", "C", "D"],
  Name       = Union{Missing, String}["John", "Tom", "Jim", "望研測来白制父委供情治当認米注。規"],
  Photo      = Union{Missing, Vector{UInt8}}[b"abc", b"def", b"ghi", b"jkl"],
  JobType    = Union{Missing, String}["HR", "HR", "Management", "Accounts"],
  Senior     = Union{Missing, Bool}[true, true, false, true],
)

cursor = DBInterface.execute(conn, "select * from Employee")
@test eltype(cursor) == ODBC.Row
@test Tables.istable(cursor)
@test Tables.rowaccess(cursor)
@test Tables.rows(cursor) === cursor
@test Tables.schema(cursor) == Tables.Schema(propertynames(expected), eltype.(collect(expected)))
@test Base.IteratorSize(typeof(cursor)) == Base.HasLength()
@test length(cursor) == 4

row = first(cursor)
@test Base.IndexStyle(typeof(row)) == Base.IndexLinear()
@test length(row) == length(expected)
@test propertynames(row) == collect(propertynames(expected))
for (i, prop) in enumerate(propertynames(row))
    @test getproperty(row, prop) == row[prop] == row[i] == expected[prop][1]
end

res = DBInterface.execute(conn, "select * from Employee") |> columntable
@test length(res) == 16
@test length(res[1]) == 4
@test res == expected

# as a prepared statement
stmt = DBInterface.prepare(conn, "select * from Employee")
cursor = DBInterface.execute(stmt)
@test eltype(cursor) == ODBC.Row
@test Tables.istable(cursor)
@test Tables.rowaccess(cursor)
@test Tables.rows(cursor) === cursor
@test Tables.schema(cursor) == Tables.Schema(propertynames(expected), eltype.(collect(expected)))
@test Base.IteratorSize(typeof(cursor)) == Base.HasLength()
@test length(cursor) == 4

row = first(cursor)
@test Base.IndexStyle(typeof(row)) == Base.IndexLinear()
@test length(row) == length(expected)
@test propertynames(row) == collect(propertynames(expected))
for (i, prop) in enumerate(propertynames(row))
    @test getproperty(row, prop) == row[prop] == row[i] == expected[prop][1]
end

res = DBInterface.execute(stmt) |> columntable
@test length(res) == 16
@test length(res[1]) == 4
@test res == expected

@test DBInterface.close!(stmt) === nothing
@test_throws ErrorException DBInterface.execute(stmt)

# insert null row
DBInterface.execute(conn, "INSERT INTO Employee () VALUES ();")
for i = 1:length(expected)
    if i == 1
        push!(expected[i], 5)
    elseif i == 11
    else
        push!(expected[i], missing)
    end
end

res = DBInterface.execute(conn, "select * from Employee") |> columntable
@test length(res) == 16
@test length(res[1]) == 5
for i = 1:length(expected)
    if i != 11
        @test isequal(res[i], expected[i])
    end
end

stmt = DBInterface.prepare(conn, "select * from Employee")
res = DBInterface.execute(stmt) |> columntable
DBInterface.close!(stmt)
@test length(res) == 16
@test length(res[1]) == 5
for i = 1:length(expected)
    if i != 11
        @test isequal(res[i], expected[i])
    end
end

# now test insert/parameter binding
DBInterface.execute(conn, "DELETE FROM Employee")
for i = 1:length(expected)
    if i != 11
        pop!(expected[i])
    end
end

stmt = DBInterface.prepare(conn,
    "INSERT INTO Employee (OfficeNo, DeptNo, EmpNo, Wage, Salary, Rate, LunchTime, JoinDate, LastLogin, LastLogin2, Initial, Name, Photo, JobType, Senior)
     VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)")

DBInterface.executemany(stmt, Base.structdiff(expected, NamedTuple{(:ID,)}))

stmt2 = DBInterface.prepare(conn, "select * from Employee")
res = DBInterface.execute(stmt2) |> columntable
DBInterface.close!(stmt2)
@test length(res) == 16
@test length(res[1]) == 4
for i = 1:length(expected)
    if i != 11 && i != 1
        @test isequal(res[i], expected[i])
    end
end

DBInterface.execute(stmt, [missing, missing, missing, missing, missing, missing, missing, missing, missing, DateTime("2015-09-05T12:31:30"), missing, missing, missing, missing, missing])
DBInterface.close!(stmt)

stmt = DBInterface.prepare(conn, "select * from Employee")
res = DBInterface.execute(stmt) |> columntable
DBInterface.close!(stmt)
for i = 1:length(expected)
    if i != 11 && i != 1
        @test res[i][end] === missing
    end
end

DBInterface.execute(conn, """
CREATE PROCEDURE get_employee()
BEGIN
   select * from Employee;
END
""")
res = DBInterface.execute(conn, "call get_employee()") |> columntable
@test length(res) > 0
@test length(res[1]) == 5
res = DBInterface.execute(conn, "call get_employee()") |> columntable
@test length(res) > 0
@test length(res[1]) == 5
# test that we can call multiple stored procedures in a row w/o collecting results (they get cleaned up properly internally)
res = DBInterface.execute(conn, "call get_employee()")
res = DBInterface.execute(conn, "call get_employee()")

# and for prepared statements
stmt = DBInterface.prepare(conn, "call get_employee()")
res = DBInterface.execute(stmt) |> columntable
@test length(res) > 0
@test length(res[1]) == 5
res = DBInterface.execute(stmt) |> columntable
@test length(res) > 0
@test length(res[1]) == 5
res = DBInterface.execute(stmt)
res = DBInterface.execute(stmt)

results = DBInterface.executemultiple(conn, """
select ID from Employee;
select DeptNo, OfficeNo from Employee where OfficeNo IS NOT NULL
""")
state = iterate(results)
@test state !== nothing
res, st = state
@test !st
# @test_broken length(res) == 5
ret = columntable(res)
# @test_broken length(ret[1]) == 5
state = iterate(results, st)
@test state !== nothing
res, st = state
@test !st
# @test_broken length(res) == 4
ret = columntable(res)
# @test_broken length(ret[1]) == 4

DBInterface.execute(conn, """CREATE TABLE Employee2
                 (
                     ID INT NOT NULL AUTO_INCREMENT,
                     望研 VARCHAR(255) CHARACTER SET utf8mb4,
                     PRIMARY KEY (ID)
                 )""")
DBInterface.execute(conn, "INSERT INTO Employee2 (望研) VALUES ('hey'), ('ho')")
ret = DBInterface.execute(conn, "select * from Employee2") |> columntable
@test length(ret.望研) == 2
