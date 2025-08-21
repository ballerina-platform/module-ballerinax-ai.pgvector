// Copyright (c) 2025 WSO2 LLC (http://www.wso2.com).
//
// WSO2 LLC. licenses this file to you under the Apache License,
// Version 2.0 (the "License"); you may not use this file except
// in compliance with the License.
// You may obtain a copy of the License at
//
// http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing,
// software distributed under the License is distributed on an
// "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
// KIND, either express or implied.  See the License for the
// specific language governing permissions and limitations
// under the License.

import ballerina/ai;
import ballerina/sql;
import ballerinax/postgresql;

# Represents vector data without ID
#
# + id - Unique identifier
# + embedding - Vector embedding array
# + metadata - Optional metadata
# + similarity - Optional similarity score
type SearchResult record {
    string id;
    string embedding;
    string metadata?;
    float similarity?;
};

# Configuration for the vector store
#
# + topK - Maximum number of results to return
# + embeddingType - Type of the embedding to be used
public type Configuration record {|
    *ConnectionConfig;
    int topK = 10;
    ai:VectorStoreQueryMode embeddingType = ai:DENSE;
|};

# Connection configuration for the vector store
#
# + host - The host of the database
# + port - The port of the database
# + user - The username of the database
# + password - The password of the database
# + database - The name of the database
# + tableName - The name of the table
# + options - The options for the connection
# + connectionPool - The connection pool configurations for the database
public type ConnectionConfig record {|
    string host;
    int port = 5432;
    string user;
    string password;
    string database;
    string tableName?;
    postgresql:Options options = {};
    sql:ConnectionPool connectionPool = {};
|};

