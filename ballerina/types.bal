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

import ballerina/sql;

# Represents similarity search types for vector comparisons
#
# + EUCLIDEAN_DISTANCE - L2 distance (Euclidean distance)
# + COSINE_DISTANCE - Cosine distance (1 - cosine similarity)
# + NEGATIVE_INNER_PRODUCT - Negative inner product
public enum SimilarityType {
    EUCLIDEAN_DISTANCE = "<->",
    COSINE_DISTANCE = "<=>",
    NEGATIVE_INNER_PRODUCT = "<#>"
}

# Represents vector data without ID
#
# + id - Unique identifier
# + embedding - Vector embedding array
# + metadata - Optional metadata
# + similarity - Optional similarity score
public type SearchResult record {
    string id;
    string embedding;
    string metadata?;
    float similarity?;
};

# Search configuration for vector queries
#
# + similarityType - Type of similarity measure to use
# + limit - Maximum number of results to return
# + threshold - Optional similarity threshold
# + metadata - Optional metadata filters
public type SearchConfig record {|
    SimilarityType similarityType = COSINE_DISTANCE;
    int 'limit = 10;
    float? threshold = ();
    map<sql:Value> metadata = {};
|};

# Connection configuration for the vector store
#
# + host - Database host
# + user - Database username
# + password - Database password
# + database - Database name
# + tableName - Table name
# + additionalColumns - Additional columns to be added to the table
# + port - Database port
# + topK - Maximum number of results to return
public type ConnectionConfig record {|
    string host;
    string user;
    string password;
    string database;
    string tableName?;
    Column[] additionalColumns?;
    int port = 5432;
    int topK = 10;
|};

# Represents a column in the database
#
# + name - Name of the column
# + type - Type of the column
public type Column record {|
    string name;
    ColumnType 'type;
|};

# Represents the type of the column in postgres database
public enum ColumnType {
    INTEGER,
    BIGINT,
    SERIAL,
    VARCHAR,
    TEXT,
    BOOLEAN,
    TIMESTAMP,
    DATE,
    JSONB,
    UUID
}
