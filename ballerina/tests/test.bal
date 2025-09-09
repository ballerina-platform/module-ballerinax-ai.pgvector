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
import ballerina/test;
import ballerina/uuid;
import ballerina/time;

string tableName = "dense_table_70";
string sparseTableName = "sparse_table_70";
string id = uuid:createRandomUuid();
string host = "localhost";
string user = "postgres";
string password = "postgres";
string database = "vector_store";

VectorStore vectorStore = check new (
    host,
    user,
    password,
    database,
    tableName,
    configs = {
        vectorDimension: 1536
    }
);

VectorStore sparseVectorStore = check new (
    host,
    user,
    password,
    database,
    sparseTableName,
    configs = {
        embeddingType: ai:SPARSE,
        vectorDimension: 200
    }
);

final float[] vectorEmbedding = check generateEmbedding(1536);
final float[] sparseVectorEmbedding = check generateEmbedding(200);

time:Utc createdAt = time:utcNow(1);

function generateEmbedding(int dimension) returns float[]|error {
    float[] embedding = [];
    foreach int i in 1...dimension {
        embedding.push(check (i % 10).cloneWithType(float));
    }
    return embedding;
}

@test:Config {
    groups: ["add"]
}
function testAddEntry() returns error? {
    ai:Error? result = vectorStore.add([
        {
            id,
            embedding: vectorEmbedding,
            chunk: {
                'type: "text",
                content: "This is a chunk",
                metadata: {
                    createdAt
                }
            }
        }
    ]);
    test:assertTrue(result !is ai:Error);
}

@test:Config {}
function testAddSparseEntry() returns error? {
    ai:Error? result = sparseVectorStore.add([
        {
            id,
            embedding: {
                indices: [0, 2],
                values: sparseVectorEmbedding
            },
            chunk: {
                'type: "text",
                content: "This is a chunk",
                metadata: {
                    createdAt
                }
            }
        }
    ]);
    test:assertTrue(result !is ai:Error);
}

@test:Config {
    dependsOn: [testAddEntry]
}
function testQueryEntries() returns error? {
    ai:VectorMatch[] query = check vectorStore.query({
        embedding: vectorEmbedding,
        filters: {
            filters: [
                {
                    'key: "createdAt",
                    operator: ai:EQUAL,
                    value: createdAt
                }
            ]
        }
    });
    test:assertEquals(query[0].similarityScore, 1.0);
}

@test:Config {
    dependsOn: [testAddSparseEntry]
}
function testQueryEntriesWithSparseEmbedding() returns error? {
    ai:VectorMatch[] query = check sparseVectorStore.query({
        embedding: {
            indices: [0, 2],
            values: sparseVectorEmbedding
        },
        topK: 1
    });
    test:assertEquals(query[0].similarityScore, 1.0);
}

@test:Config {
    dependsOn: [testAddEntry]
}
function testQueryEntriesWithoutEmbeddingsAndFilters() returns error? {
    _ = check vectorStore.add([
        {
            id,
            embedding: vectorEmbedding,
            chunk: {
                'type: "text",
                content: "This is a chunk"
            }
        }
    ]);
    ai:VectorMatch[] query = check vectorStore.query({
        topK: 1
    });
    test:assertEquals(query[0].similarityScore, 0.0);
}

@test:Config {
    dependsOn: [testAddSparseEntry]
}
function testQueryEntriesWithFilters() returns error? {
    ai:VectorMatch[] query = check sparseVectorStore.query({
        topK: 1,
        filters: {
            filters: [
                {
                    'key: "createdAt",
                    operator: ai:EQUAL,
                    value: createdAt
                }
            ]
        }
    });
    test:assertEquals(query[0].similarityScore, 0.0);
}

@test:Config {
    dependsOn: [testQueryEntries]
}
function testDeleteEntry() returns error? {
    ai:Error? delete = vectorStore.delete([id, id]);
    test:assertTrue(delete !is ai:Error);

    delete = sparseVectorStore.delete(id);
    test:assertTrue(delete !is ai:Error);
}
