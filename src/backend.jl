function ODBCAllocHandle(handletype,parenthandle)
	handle = Array(Ptr{Void},1)
	if @FAILED SQLAllocHandle(handletype,parenthandle,handle)
		error("[ODBC]: ODBC Handle Allocation Failed; Return Code: $ret")
	else		
		#If allocation succeeded, retrieve handle pointer stored in handle's array index 1
		handle = handle[1]
		if handletype == SQL_HANDLE_ENV 
			if @FAILED SQLSetEnvAttr(handle,SQL_ATTR_ODBC_VERSION,SQL_OV_ODBC3)
				#If version-setting fails, release environment handle and set global env variable to a null pointer
				SQLFreeHandle(SQL_HANDLE_ENV,handle)
				global env = C_NULL
				error("[ODBC]: Failed to set ODBC version; Return Code: $ret")
			end
		end
	end
	return handle
end
#ODBCConnect: Connect to qualified DSN (pre-established through ODBC Admin), with optional username and password inputs
function ODBCConnect!(dbc::Ptr{Void},dsn::String,username::String,password::String)
	if @FAILED SQLConnect(dbc,dsn,username,password)
		ODBCError(SQL_HANDLE_DBC,dbc)
		error("[ODBC]: SQLConnect failed; Return Code: $ret")
	end
end
#ODBCDriverConnect: Alternative connect function that allows user to create datasources on the fly through opening the ODBC admin
function ODBCDriverConnect!(dbc::Ptr{Void},conn_string::String,driver_prompt::Uint16)
	window_handle = C_NULL	
	@windows_only window_handle = ccall( (:GetForegroundWindow, "user32"), Ptr{Void}, () )
	@windows_only driver_prompt = SQL_DRIVER_PROMPT
	out_buff = Array(Int16,1)
	if @FAILED SQLDriverConnect(dbc,window_handle,conn_string,C_NULL,out_buff,driver_prompt)
		ODBCError(SQL_HANDLE_DBC,dbc)
		error("[ODBC]: SQLDriverConnect failed; Return Code: $ret")
	end
end
#ODBCQueryExecute: Send query to DMBS
function ODBCQueryExecute(stmt::Ptr{Void},querystring::String)
	if @FAILED SQLExecDirect(stmt,querystring)
		ODBCError(SQL_HANDLE_STMT,stmt)
		error("[ODBC]: SQLExecDirect failed; Return Code: $ret")
	end
end
#ODBCMetadata: Retrieve resultset metadata once query is processed, Metadata type is returned
function ODBCMetadata(stmt::Ptr{Void},querystring::String)
		#Allocate space for and fetch number of columns and rows in resultset
		cols = Array(Int16,1)
		rows = Array(Int,1)
		SQLNumResultCols(stmt,cols)
		SQLRowCount(stmt,rows)
		#Allocate arrays to hold each column's metadata
		colnames = UTF8String[]
		coltypes = Array((String,Int16),0)
		colsizes = Int[]
		coldigits = Int16[]
		colnulls = Int16[]
		#Allocate space for and fetch the name, type, size, etc. for each column
		for x in 1:cols[1]
			column_name = zeros(Uint8,256)
			name_length = Array(Int16,1)
			datatype = Array(Int16,1)
			column_size = Array(Int,1)
			decimal_digits = Array(Int16,1)
			nullable = Array(Int16,1) 
			SQLDescribeCol(stmt,x,column_name,name_length,datatype,column_size,decimal_digits,nullable)
			push!(colnames,ODBCClean(column_name,1))
			push!(coltypes,(get(SQL_TYPES,int(datatype[1]),"SQL_CHAR"),datatype[1]))
			push!(colsizes,int(column_size[1]))
			push!(coldigits,decimal_digits[1])
			push!(colnulls,nullable[1])
		end
	return Metadata(querystring,int(cols[1]),rows[1],colnames,coltypes,colsizes,coldigits,colnulls)
end
#ODBCFetch: Using resultset metadata, allocate space/arrays for previously generated resultset, retrieve results
function ODBCBindCols(stmt::Ptr{Void},meta::Metadata)
	#with catalog functions or all-filtering WHERE clauses, resultsets can have 0 rows/cols
	meta.rows == 0 && return (Any[],Any[],0)
	rowset = MULTIROWFETCH > meta.rows ? (meta.rows < 0 ? 1 : meta.rows) : MULTIROWFETCH
	SQLSetStmtAttr(stmt,SQL_ATTR_ROW_ARRAY_SIZE,uint(rowset),SQL_IS_UINTEGER)

	#these Any arrays are where the ODBC manager dumps result data
	indicator = Any[]
	columns = Any[]
	for x in 1:meta.cols
		sqltype = meta.coltypes[x][2]
		#we need the C type so the ODBC manager knows how to store the data
		ctype = get(SQL2C,sqltype,SQL_C_CHAR)
		#we need the julia type that corresponds to the C type size
		jtype = get(SQL2Julia,sqltype,Uint8)
		holder, jlsize = ODBCColumnAllocate(jtype,meta.colsizes[x]+1,rowset)
		ind = Array(Int,rowset)
		if @SUCCEEDED ODBC.SQLBindCols(stmt,x,ctype,holder,int(jlsize),ind)
			push!(columns,holder)
			push!(indicator,ind)
		else #SQL_ERROR
			ODBCError(SQL_HANDLE_STMT,stmt)
			error("[ODBC]: SQLBindCol $x failed; Return Code: $ret")
		end
	end
	return (columns, indicator, rowset)
end

ODBCColumnAllocate(x,y,z) 				= (Array(x,z),sizeof(x))
ODBCColumnAllocate(x::Type{Uint8},y,z) 	= (zeros(x,(y,z)),y)
ODBCColumnAllocate(x::Type{Uint16},y,z) = (zeros(x,(y,z)),y*2)
ODBCColumnAllocate(x::Type{Uint32},y,z) = (zeros(x,(y,z)),y*4)

ODBCStorage(x) 							= eltype(typeof(x))[]
ODBCStorage(x::Array{Uint8,2}) 			= UTF8String[]
ODBCStorage(x::Array{Uint16,2}) 		= UTF16String[]
ODBCStorage(x::Array{Uint32,2}) 		= UTF8String[]
ODBCStorage(x::Array{SQLDate,1}) 		= Date{ISOCalendar}[]
ODBCStorage(x::Array{SQLTime,1}) 		= SQLTime[]
ODBCStorage(x::Array{SQLTimestamp,1}) 	= DateTime{ISOCalendar,UTC}[]

ODBCEmpty(x::Array{Uint8}) = utf8("")
ODBCEmpty(x::Array{Uint16}) = utf16("")
ODBCEmpty(x::Array{Uint32}) = utf8("")
ODBCEmpty(x::Array{Int32}) = int32(0)
ODBCEmpty(x::Array{Int64}) = 0
ODBCEmpty(x::Array{Float32}) = NaN32
ODBCEmpty(x::Array{Float64}) = NaN

ODBCClean(x,y) = x[y]
ODBCClean(x::Array{Uint8},y) 			= strip(utf8(filter!(x->x!=0x00,x[:,y])))
ODBCClean(x::Array{Uint16},y) 			= UTF16String(filter!(x->x!=0x0000,x[:,y]))
ODBCClean(x::Array{Uint32},y)			= strip(utf8(filter!(x->x!=0x00,convert(Array{Uint8},x[:,y]))))
ODBCClean(x::Array{SQLDate,1},y) 		= date(x[y].year,0 < x[y].month < 13 ? x[y].month : 1,x[y].day)
ODBCClean(x::Array{SQLTimestamp,1},y)	= datetime(int64(x[y].year),int64(0 < x[y].month < 13 ? x[y].month : 1),int64(x[y].day),
													int64(x[y].hour),int64(x[y].minute),int64(x[y].second),int64(div(x[y].fraction,1000000)))

ODBCEscape(x) = string(x)
ODBCEscape(x::String) = "\"" * x * "\""

#function for fetching a resultset into a DataFrame
function ODBCFetchDataFrame(stmt::Ptr{Void},meta::Metadata,columns::Array{Any,1},rowset::Int,
                            indicator::Vector{Any})
	cols = Any[]
        nas = BitVector[]
	for i = 1:meta.cols
		push!(cols, ODBCStorage(columns[i]))
                push!( nas, BitVector( 0 ) )
	end
	while @SUCCEEDED SQLFetchScroll(stmt,SQL_FETCH_NEXT,0)
		for col in 1:meta.cols, row in 1:rowset
                    if( indicator[col][1] < 0 )
                        push!(nas[col], true)
                        push!(cols[col], ODBCEmpty(columns[col]))
                    else
                        push!(nas[col], false)
                        coltype = typeof(columns[col])
                        # for strings, we need to restrict the length
                        if( issubtype(coltype,Array) && eltype(coltype) in [Uint8,Uint16,Uint32] )
                            l = indicator[col][1]
                            data = reshape( columns[col][1:l,row], (l,1) )
			    push!(cols[col], ODBCClean(data,1))
                        else
			    push!(cols[col], ODBCClean(columns[col],row))
                        end
                    end
		end
	end
        dataarrays = {DataArray(cols[col],nas[col]) for col in 1:length(cols)}
	resultset = DataFrame(dataarrays, Index(meta.colnames))
end
function ODBCDirectToFile(stmt::Ptr{Void},meta::Metadata,columns::Array{Any,1},rowset::Int,output::String,delim::Char,l::Int)
	out_file = l == 0 ? open(output,"w") : open(output,"a")
	write(out_file,join(meta.colnames,delim)*"\n")
	while @SUCCEEDED SQLFetchScroll(stmt,SQL_FETCH_NEXT,0)
		for row in 1:rowset, col in 1:meta.cols
			write(out_file,ODBCEscape(ODBCClean(columns[col],row)))
	        write(out_file,delim)
	        col == meta.cols && write(out_file,"\n")
		end
	end
	close(out_file)
	return DataFrame()
end
#ODBCFreeStmt!: used to 'clear' a statement of bound columns, resultsets, and other bound parameters in preparation for a subsequent query
function ODBCFreeStmt!(stmt)
	SQLFreeStmt(stmt,SQL_CLOSE)
	SQLFreeStmt(stmt,SQL_UNBIND)
	SQLFreeStmt(stmt,SQL_RESET_PARAMS)
end
#Error Reporting: Takes an SQL handle as input and retrieves any error messages associated with that handle; there may be more than one
function ODBCError(handletype::Int16,handle::Ptr{Void})
	i = int16(1)
	state = zeros(Uint8,6)
	error_msg = zeros(Uint8, 1024)
	native = Array(Int,1)
	msg_length = Array(Int16,1)
	while @SUCCEEDED SQLGetDiagRec(handletype,handle,i,state,native,error_msg,msg_length)
		st = ODBCClean(state,1)
		msg = ODBCClean(error_msg,1)
		println("[ODBC] $st: $msg")
		i = int16(i+1)
	end
end
