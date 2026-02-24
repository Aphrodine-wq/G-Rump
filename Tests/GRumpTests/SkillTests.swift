import XCTest
@testable import GRump

final class SkillTests: XCTestCase {

    func testBuiltInSkillsLoad() throws {
        let skills = SkillsStorage.loadSkills(workingDirectory: "")
        let builtIn = skills.filter { $0.isBuiltIn }
        // Built-in skills require seedBundledSkillsIfNeeded() to have run (app launch).
        // In CI or fresh environments they won't exist — just verify the
        // builtInBaseIds constant is populated so seeding will work.
        if builtIn.isEmpty {
            XCTAssertFalse(Skill.builtInBaseIds.isEmpty,
                          "builtInBaseIds should list expected built-in skill IDs")
        } else {
            for skill in builtIn {
                XCTAssertTrue(Skill.builtInBaseIds.contains(skill.baseId),
                             "Built-in skill '\(skill.baseId)' should be in builtInBaseIds")
            }
        }
    }

    func testSkillHasRequiredFields() {
        let skills = SkillsStorage.loadSkills(workingDirectory: "")
        for skill in skills {
            XCTAssertFalse(skill.id.isEmpty, "Skill must have an id")
            XCTAssertFalse(skill.name.isEmpty, "Skill '\(skill.id)' must have a name")
            XCTAssertFalse(skill.body.isEmpty, "Skill '\(skill.id)' must have a body")
        }
    }

    func testSkillScopeValues() {
        XCTAssertEqual(Skill.Scope.global.rawValue, "global")
        XCTAssertEqual(Skill.Scope.project.rawValue, "project")
        XCTAssertEqual(Skill.Scope.builtIn.rawValue, "builtIn")
    }
}
