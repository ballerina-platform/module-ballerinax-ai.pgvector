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
import ballerinax/postgresql;

string tableName = "pgvector_table";
string id = uuid:createRandomUuid();
string host = "localhost";
string user = "postgres";
string password = "postgres";
string database = "vector_store";

VectorStore vectorStore = check new (
    options = {
        connectTimeout: 10,
        ssl: {
            mode: postgresql:DISABLE
        }
    },
    connectionConfigs = {
        host,
        user,
        password,
        database,
        tableName,
        additionalColumns: [
            {
                name: "created_at",
                'type: DATE
            },
            {
                name: "updated_at",
                'type: DATE
            }
        ]
    },
    vectorDimension = 3
);

final float[] embedding = [0, 0.5, 0.25];

@test:Config {
    groups: ["add"]
}
function testAddEntry() returns error? {
    ai:Error? result = vectorStore.add([
        {
            id,
            embedding,
            chunk: {'type: "text", content: "This is a chunk"}
        }
    ]);
    test:assertTrue(result !is ai:Error);
}

@test:Config {
    dependsOn: [testAddEntry]
}
function testQueryEntries() returns error? {
    ai:VectorMatch[] query = check vectorStore.query({
        embedding,
        filters: {
            filters: [
                {
                    'key: "id",
                    operator: ai:EQUAL,
                    value: id
                },
                {
                    'key: "embedding",
                    operator: ai:EQUAL,
                    value: embedding.toJsonString()
                }
            ]
        }
    });
    test:assertEquals(query[0].similarityScore, 1.0);
}

@test:Config {
    dependsOn: [testQueryEntries]
}
function testDeleteEntry() returns error? {
    ai:Error? delete = vectorStore.delete(id);
    test:assertTrue(delete !is ai:Error);
}
