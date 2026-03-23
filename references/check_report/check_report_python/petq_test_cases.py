"""
寵物檢疫智慧客服品質評估測試案例集

所有測試案例均來自官方來源，非自行編撰：
- Source 1: APHIA 高雄分署英文 FAQ (Q1-Q36) — 翻譯並改寫為自然用戶提問
- Source 2: 獸醫研究所 (NVRI) 狂犬病檢測常見問題 (13 題)
- Source 3: 對抗性/邊界測試 — 基於官方規定設計的陷阱題
- Source 4: 多語系測試 — 英/越/泰/日/印尼語
- Source 5: 情境模擬 — 基於官方 FAQ 延伸的複合情境

產生日期: 2026-03-19
"""

from dataclasses import dataclass


@dataclass
class QualityTestCase:
    id: str
    category: str  # 官方FAQ / NVRI / 對抗性 / 多語系 / 情境模擬
    question: str
    reference_answer: str  # Key points the answer MUST contain
    source: str  # Where this question comes from
    difficulty: str  # easy / normal / hard / adversarial


QUALITY_TEST_CASES = [
    # =========================================================================
    # Source 1: APHIA Kaohsiung Branch English FAQ (Q1-Q36)
    # 官方英文 FAQ 翻譯改寫為自然中文用戶提問
    # =========================================================================
    QualityTestCase(
        id="APHIA-Q01",
        category="官方FAQ",
        question="輸入同意文件要多久才能辦好？",
        reference_answer="須在出發前至少 20 天申請。高雄分署收到申請後會儘速核發。",
        source="APHIA Kaohsiung FAQ Q1 & Q12",
        difficulty="easy",
    ),
    QualityTestCase(
        id="APHIA-Q02",
        category="官方FAQ",
        question="申請犬貓輸入許可要多少錢？",
        reference_answer="申請輸入同意文件免費，不收取費用。",
        source="APHIA Kaohsiung FAQ Q2",
        difficulty="easy",
    ),
    QualityTestCase(
        id="APHIA-Q03",
        category="官方FAQ",
        question="一定要找報關行幫忙辦輸入許可嗎？還是可以自己辦？",
        reference_answer="不一定需要報關行，飼主可以自行申請。也可透過 Email 或傳真方式辦理。",
        source="APHIA Kaohsiung FAQ Q3",
        difficulty="easy",
    ),
    QualityTestCase(
        id="APHIA-Q04",
        category="官方FAQ",
        question="我要從高雄小港機場帶狗入境，要怎麼辦輸入許可？",
        reference_answer="請聯繫防檢署高雄分署，電話 886-7-9720200 或 886-7-8057790。",
        source="APHIA Kaohsiung FAQ Q4",
        difficulty="easy",
    ),
    QualityTestCase(
        id="APHIA-Q05",
        category="官方FAQ",
        question="有比較方便的方式申請輸入許可嗎？不想跑一趟",
        reference_answer="可以用 Email (kh0701@khaphia.gov.tw) 或傳真 (886-7-8068427) 寄送文件申請。也可使用線上申請系統 pet-epermit.aphia.gov.tw。",
        source="APHIA Kaohsiung FAQ Q5",
        difficulty="easy",
    ),
    QualityTestCase(
        id="APHIA-Q06",
        category="官方FAQ",
        question="犬貓輸入的申請表去哪裡下載？",
        reference_answer="可至防檢署官網下載，或至「輸入犬貓檢疫資訊網」(pet-epermit.aphia.gov.tw) 線上申請。",
        source="APHIA Kaohsiung FAQ Q6",
        difficulty="easy",
    ),
    QualityTestCase(
        id="APHIA-Q07",
        category="官方FAQ",
        question="申請輸入許可需要準備哪些文件？",
        reference_answer="需要：1. 獸醫師簽發之狂犬病不活化疫苗接種證明（含品種、性別、年齡、晶片號碼、接種日期）2. 飼主護照或身分證影本 3. 疫區國家另需 FAVN 抗體力價檢測報告（≥0.5 IU/mL，採血日在出發前 90 天至 1 年內）。",
        source="APHIA Kaohsiung FAQ Q7",
        difficulty="normal",
    ),
    QualityTestCase(
        id="APHIA-Q08",
        category="官方FAQ",
        question="打完狂犬病疫苗之後多久可以抽血驗抗體？",
        reference_answer="採血時間取決於所施打的疫苗種類，建議接種後諮詢獸醫師確認合適的採血時間。一般建議疫苗施打後至少 30 天再採血。",
        source="APHIA Kaohsiung FAQ Q8",
        difficulty="normal",
    ),
    QualityTestCase(
        id="APHIA-Q09",
        category="官方FAQ",
        question="目前有哪些國家是狂犬病非疫區？",
        reference_answer="台灣認定之狂犬病非疫區共 11 個國家/地區：日本、英國、瑞典、冰島、澳大利亞、紐西蘭、挪威（Svalbard 群島除外）、美國夏威夷州、美國關島、新加坡、愛沙尼亞。其餘國家均為疫區。",
        source="APHIA Kaohsiung FAQ Q9",
        difficulty="normal",
    ),
    QualityTestCase(
        id="APHIA-Q10",
        category="官方FAQ",
        question="隔離的地方需要自己先找好嗎？",
        reference_answer="不需要自行安排。隔離場所會在輸入許可核准後安排，飼主可在許可文件上查看隔離日期和地點。",
        source="APHIA Kaohsiung FAQ Q10",
        difficulty="easy",
    ),
    QualityTestCase(
        id="APHIA-Q11",
        category="官方FAQ",
        question="輸入犬貓需要打什麼疫苗？初次施打跟補強接種的時間要求一樣嗎？",
        reference_answer="須施打狂犬病不活化疫苗。疫區國家：初次接種須犬貓滿 90 日齡以上，接種日到出發日須間隔 90 天以上且不超過 1 年；補強接種則間隔 30 天以上且不超過 1 年。非疫區國家：須滿 90 日齡，接種日到出發日間隔 30 天以上且不超過 1 年。",
        source="APHIA Kaohsiung FAQ Q11",
        difficulty="hard",
    ),
    QualityTestCase(
        id="APHIA-Q13",
        category="官方FAQ",
        question="如果沒有輸入許可就帶寵物到機場會怎樣？",
        reference_answer="沒有輸入許可的犬貓將被退運（送回出發國）或銷毀。",
        source="APHIA Kaohsiung FAQ Q13",
        difficulty="normal",
    ),
    QualityTestCase(
        id="APHIA-Q14",
        category="官方FAQ",
        question="拿到輸入許可後可以改日期嗎？",
        reference_answer="可以變更，但須在原輸入許可有效期屆滿前 20 天內，向原核發機關提出申請，並檢附原輸入許可影本。以 1 次為限。",
        source="APHIA Kaohsiung FAQ Q14",
        difficulty="normal",
    ),
    QualityTestCase(
        id="APHIA-Q15",
        category="官方FAQ",
        question="從非疫區出發但中間在疫區國家轉機，會有什麼影響？",
        reference_answer="經疫區國家轉機的犬貓，若無法提供未出港站或未接觸其他動物之證明，將被退運、銷毀或須在指定隔離場所隔離 7 天。建議選擇直飛或備妥轉運證明文件/封條。",
        source="APHIA Kaohsiung FAQ Q15",
        difficulty="hard",
    ),
    QualityTestCase(
        id="APHIA-Q16",
        category="官方FAQ",
        question="帶寵物入境台灣有數量限制嗎？",
        reference_answer="原則上沒有數量限制，但疫區國家輸入須先確認隔離場所有空位。一般建議每人不超過 2 隻（合理自用數量），超過可能被視為商業輸入。",
        source="APHIA Kaohsiung FAQ Q16",
        difficulty="normal",
    ),
    QualityTestCase(
        id="APHIA-Q17",
        category="官方FAQ",
        question="輸入的犬貓一定要植入晶片嗎？",
        reference_answer="是的，必須植入晶片。須符合 ISO 11784/11785 規格或 AVID 9/10 晶片。",
        source="APHIA Kaohsiung FAQ Q17",
        difficulty="easy",
    ),
    QualityTestCase(
        id="APHIA-Q18",
        category="官方FAQ",
        question="寵物一定要跟飼主同班飛機來嗎？可以單獨寄送嗎？",
        reference_answer="不一定要同行，犬貓可以由飼主隨身攜帶、託運行李，或透過貨運方式單獨寄送。",
        source="APHIA Kaohsiung FAQ Q18",
        difficulty="easy",
    ),
    QualityTestCase(
        id="APHIA-Q19",
        category="官方FAQ",
        question="寵物搭飛機的運費大概多少？",
        reference_answer="犬貓可透過航空貨運或隨身攜帶方式來台。具體運費請向航空公司確認，依航線和重量而異。",
        source="APHIA Kaohsiung FAQ Q19",
        difficulty="easy",
    ),
    QualityTestCase(
        id="APHIA-Q20",
        category="官方FAQ",
        question="疫區來的犬貓要在哪裡做抗體檢測？",
        reference_answer="須在 WOAH（世界動物衛生組織）認可之狂犬病參考實驗室進行 FAVN 抗體力價檢測，結果須 ≥0.5 IU/mL。台灣的獸醫研究所 (NVRI) 亦為認可實驗室。採血日須在輸入前 90 天至 1 年。",
        source="APHIA Kaohsiung FAQ Q20",
        difficulty="normal",
    ),
    QualityTestCase(
        id="APHIA-Q21",
        category="官方FAQ",
        question="運送途中怎麼確保犬貓的健康？",
        reference_answer="建議出發前諮詢獸醫師，確認犬貓適合長途運輸。運輸籠須符合 IATA 規定，短鼻品種須注意航空公司限制，夏季高溫期部分航空公司暫停寵物託運。",
        source="APHIA Kaohsiung FAQ Q21",
        difficulty="easy",
    ),
    QualityTestCase(
        id="APHIA-Q22",
        category="官方FAQ",
        question="帶進台灣的犬貓有年齡限制嗎？",
        reference_answer="犬貓須至少滿 90 日齡。未滿 90 日齡者可輸入，但須隔離至滿 90 日齡後施打疫苗再繼續隔離（疫區 180 天、非疫區 30 天），隔離期非常長。",
        source="APHIA Kaohsiung FAQ Q22",
        difficulty="normal",
    ),
    QualityTestCase(
        id="APHIA-Q23",
        category="官方FAQ",
        question="犬貓到機場之後要準備哪些文件去報到？",
        reference_answer="抵達機場後須向檢疫機關提交：1. 輸入同意文件 2. 輸出國政府動物檢疫機關簽發之動物健康證明書正本 3. 海運/空運提單或海關申報單。無正本健康證明書者將被退運或銷毀。",
        source="APHIA Kaohsiung FAQ Q23",
        difficulty="normal",
    ),
    QualityTestCase(
        id="APHIA-Q24",
        category="官方FAQ",
        question="我的狗之前從台灣帶去非疫區不到半年，現在要帶回來需要什麼？",
        reference_answer="自台灣輸出至非疫區且未滿 6 個月再輸入者，需提供：1. 原輸出檢疫證明書影本 2. 飼主身分證明文件 3. 犬隻須提供寵物登記證 4. 回台時須有健康證明書（含晶片號碼、疫苗記錄、未至第三國聲明）。",
        source="APHIA Kaohsiung FAQ Q24",
        difficulty="hard",
    ),
    QualityTestCase(
        id="APHIA-Q25",
        category="官方FAQ",
        question="從台灣帶去非疫區不到半年再帶回來，還需要做抗體檢測嗎？",
        reference_answer="若犬貓是輸出至非疫區，且期間未到第三國，不需要做 FAVN 抗體檢測。但若輸出至疫區，仍須提供抗體檢測報告。",
        source="APHIA Kaohsiung FAQ Q25",
        difficulty="hard",
    ),
    QualityTestCase(
        id="APHIA-Q26",
        category="官方FAQ",
        question="抗體報告已經達到 0.5 IU/mL 了，還是要隔離嗎？",
        reference_answer="是的，來自疫區的犬貓即使抗體合格，原則上仍須隔離 7 天。2024 年新制下，符合特定條件（如 120 天前申請且採血在 180 天至 1 年內）可免隔離。",
        source="APHIA Kaohsiung FAQ Q26",
        difficulty="normal",
    ),
    QualityTestCase(
        id="APHIA-Q27",
        category="官方FAQ",
        question="隔離場所有哪些選擇？",
        reference_answer="全台 3 處隔離場所：1. 桃園分署觀音檢疫站（桃園機場、松山機場、台北港、台中機場入境適用）2. 國立中興大學獸醫教學醫院（目前暫停服務）3. 國立屏東科技大學獸醫教學醫院（高雄小港機場入境適用）。",
        source="APHIA Kaohsiung FAQ Q27",
        difficulty="normal",
    ),
    QualityTestCase(
        id="APHIA-Q28",
        category="官方FAQ",
        question="到高雄機場後可以馬上送去隔離嗎？",
        reference_answer="若在週一至週五下午 3 點前到達，可立即送往屏東科技大學隔離場所。若在下午 3 點後或非辦公時間到達，犬貓會暫時留置在機場或貨運站。",
        source="APHIA Kaohsiung FAQ Q28",
        difficulty="normal",
    ),
    QualityTestCase(
        id="APHIA-Q29",
        category="官方FAQ",
        question="從機場到隔離場所的交通費怎麼算？",
        reference_answer="飼主須自行提供或支付交通工具費用。防檢署官員會陪同飼主和犬貓前往指定隔離場所。",
        source="APHIA Kaohsiung FAQ Q29",
        difficulty="easy",
    ),
    QualityTestCase(
        id="APHIA-Q30",
        category="官方FAQ",
        question="隔離期間需要自己準備飼料嗎？",
        reference_answer="不一定需要自備，隔離場所會提供食物。如果飼主想自備，可以把食物寄到隔離場所。",
        source="APHIA Kaohsiung FAQ Q30",
        difficulty="easy",
    ),
    QualityTestCase(
        id="APHIA-Q31",
        category="官方FAQ",
        question="有辦法縮短隔離天數嗎？",
        reference_answer="不行，隔離期間無法縮短。但 2024 年新制下，符合條件者可申請免隔離（完全免除 7 天隔離）。",
        source="APHIA Kaohsiung FAQ Q31",
        difficulty="normal",
    ),
    QualityTestCase(
        id="APHIA-Q32",
        category="官方FAQ",
        question="隔離費用大概多少？",
        reference_answer="隔離費用依場所而異，須直接聯繫隔離場所詢問：桃園觀音檢疫站 03-4761711#600、中興大學 04-22870180、屏科大 08-7740270。費用須於隔離期滿前以新臺幣現金繳交。",
        source="APHIA Kaohsiung FAQ Q32",
        difficulty="normal",
    ),
    QualityTestCase(
        id="APHIA-Q33",
        category="官方FAQ",
        question="可以用美國 USDA 核准的減毒活疫苗嗎？",
        reference_answer="不行。台灣僅接受狂犬病不活化疫苗（killed/inactivated），不接受減毒活疫苗（modified live virus vaccine），即使是 USDA 核准的也不行。",
        source="APHIA Kaohsiung FAQ Q33",
        difficulty="normal",
    ),
    QualityTestCase(
        id="APHIA-Q34",
        category="官方FAQ",
        question="從非疫區來的犬貓也要打狂犬病疫苗嗎？",
        reference_answer="是的，不論來自疫區或非疫區，犬貓都必須施打狂犬病不活化疫苗。",
        source="APHIA Kaohsiung FAQ Q34",
        difficulty="easy",
    ),
    QualityTestCase(
        id="APHIA-Q35",
        category="官方FAQ",
        question="隔離期間為什麼還要再打一次疫苗？",
        reference_answer="隔離期間會抽血複檢狂犬病抗體，若抗體低於 0.5 IU/mL，犬貓須補打狂犬病不活化疫苗。",
        source="APHIA Kaohsiung FAQ Q35",
        difficulty="normal",
    ),
    QualityTestCase(
        id="APHIA-Q36",
        category="官方FAQ",
        question="可以在台灣才抽血做抗體檢測嗎？",
        reference_answer="不行。FAVN 抗體力價檢測的血清樣本必須在國外採集，不能在台灣採集。",
        source="APHIA Kaohsiung FAQ Q36",
        difficulty="normal",
    ),

    # =========================================================================
    # Source 2: NVRI 獸醫研究所狂犬病檢測常見問題 (13 題)
    # =========================================================================
    QualityTestCase(
        id="NVRI-01",
        category="NVRI",
        question="要怎麼拿到狂犬病血清送檢的申請書？",
        reference_answer="可至獸醫研究所官網「便民服務」下「狂犬病血清抗體檢測申請」下載申請書及查看申請流程。送檢時請使用最新修訂版本。",
        source="NVRI FAQ Q1",
        difficulty="easy",
    ),
    QualityTestCase(
        id="NVRI-02",
        category="NVRI",
        question="送檢要寄血液還是血清？用什麼容器裝？",
        reference_answer="需寄送至少 1 mL 血清（非全血），裝在微量螺旋管或微量離心管即可。容器外須標示動物晶片號碼。",
        source="NVRI FAQ Q2",
        difficulty="normal",
    ),
    QualityTestCase(
        id="NVRI-03",
        category="NVRI",
        question="怎麼取得狗狗的血清？自己抽血可以嗎？",
        reference_answer="須至動物醫院由執業獸醫師採血。採血不可使用抗凝劑，待血液凝固後離心取得血清。血清混濁或溶血嚴重會影響檢測，可能需要重新採樣。",
        source="NVRI FAQ Q3",
        difficulty="normal",
    ),
    QualityTestCase(
        id="NVRI-04",
        category="NVRI",
        question="我要帶寵物去國外，獸醫研究所做的抗體報告其他國家承認嗎？",
        reference_answer="目前歐盟國家、紐西蘭、澳大利亞、新加坡、韓國及日本認可 NVRI 核發之報告。其他國家須自行查詢是否認可。",
        source="NVRI FAQ Q4",
        difficulty="normal",
    ),
    QualityTestCase(
        id="NVRI-05",
        category="NVRI",
        question="不方便親自送檢體，可以用宅配寄嗎？",
        reference_answer="可以用包裹寄送。須以冷藏 4-8°C 方式運輸（放冰寶，不可用冰塊），超過 5 天以冷凍方式保存，並附上紙本申請書。",
        source="NVRI FAQ Q5",
        difficulty="normal",
    ),
    QualityTestCase(
        id="NVRI-06",
        category="NVRI",
        question="檢體寄到獸醫研究所就算受理了嗎？怎麼知道進度？",
        reference_answer="收件日不等於受理日。須經確認申請書及檢體合格後才算受理，會以 Email 通知受理日期。若資料不符會通知補正。",
        source="NVRI FAQ Q6",
        difficulty="normal",
    ),
    QualityTestCase(
        id="NVRI-07",
        category="NVRI",
        question="狂犬病抗體檢測可以加急嗎？我很趕",
        reference_answer="不受理急件。檢測時間一律為確認受理日起算 14 個工作天（不含國定假日及週末）。若需補正文件，從補正確認日起算。",
        source="NVRI FAQ Q7",
        difficulty="normal",
    ),
    QualityTestCase(
        id="NVRI-08",
        category="NVRI",
        question="申請書寫錯了可以塗改嗎？",
        reference_answer="申請書檢測完畢後即為正式證書，建議不做塗改。若有塗改，須請獸醫師簽章證明以確保文件有效性。",
        source="NVRI FAQ Q8",
        difficulty="easy",
    ),
    QualityTestCase(
        id="NVRI-09",
        category="NVRI",
        question="在獸醫研究所做狂犬病抗體檢測要多少錢？怎麼繳費？",
        reference_answer="每件新臺幣 3,000 元（含證書費）。可至銀行或郵局臨櫃繳款，或於 e-Bill 全國繳費網繳費。須於檢體寄送前 7 日內完成繳費，並將繳費單據電子檔寄至 rabies@mail.nvri.gov.tw。",
        source="NVRI FAQ Q9",
        difficulty="normal",
    ),
    QualityTestCase(
        id="NVRI-10",
        category="NVRI",
        question="抗體檢測證明書有效期是多久？",
        reference_answer="證明書有效期限視目的地國家規定。若目的地為台灣，有效期限可參考防檢署官網規定（採血日在輸入前 90 天至 1 年內）。",
        source="NVRI FAQ Q10",
        difficulty="normal",
    ),
    QualityTestCase(
        id="NVRI-11",
        category="NVRI",
        question="證明書可以多印幾份嗎？萬一弄丟了怎麼辦？",
        reference_answer="NVRI 僅提供正本一份，請妥善保管。若遺失可依補發程序申請補發，補發程序及費用請參考 NVRI 官網。",
        source="NVRI FAQ Q11",
        difficulty="easy",
    ),
    QualityTestCase(
        id="NVRI-12",
        category="NVRI",
        question="收到的證明書上有資料錯誤，可以改嗎？",
        reference_answer="申請人或獸醫師填寫欄位有誤可申請補發。但動物晶片號碼、晶片掃描日期及採血日期不得修訂。",
        source="NVRI FAQ Q12",
        difficulty="normal",
    ),
    QualityTestCase(
        id="NVRI-13",
        category="NVRI",
        question="我人在國外，可以直接從國外寄血清到獸醫研究所嗎？",
        reference_answer="不可直接從國外寄送。須由國內代理人向防檢署申請血清輸入同意函，取得後依規定進行檢體寄送、申報及檢疫，再轉送 NVRI。報告僅寄送至國內地址。國外直接寄送者不予受理。",
        source="NVRI FAQ Q13",
        difficulty="hard",
    ),

    # =========================================================================
    # Source 3: 對抗性/陷阱題 (基於官方規定設計)
    # =========================================================================
    QualityTestCase(
        id="ADV-01",
        category="對抗性",
        question="台灣是狂犬病疫區嗎？",
        reference_answer="台灣本身自 2013 年起曾在野生動物（鼬獾）中發現狂犬病病例，但在犬貓輸出入檢疫的分類上，台灣不在非疫區名單中。對於要從台灣帶寵物出國的飼主，須視目的國對台灣的分類而定。",
        source="基於防檢署非疫區名單及台灣疫情事實",
        difficulty="adversarial",
    ),
    QualityTestCase(
        id="ADV-02",
        category="對抗性",
        question="我要帶寵物",
        reference_answer="需要更多資訊才能回答：是要帶寵物入境台灣還是出境？從哪個國家？什麼動物？建議引導用戶提供更多資訊。",
        source="模糊/不完整提問測試",
        difficulty="adversarial",
    ),
    QualityTestCase(
        id="ADV-03",
        category="對抗性",
        question="我的狗需要做 PCR 檢測才能入境嗎？",
        reference_answer="犬貓輸入台灣不需要 PCR 檢測。疫區國家需要的是 FAVN（螢光抗體病毒中和試驗）抗體力價檢測，測的是抗體而非病毒本身，與 PCR 不同。",
        source="混淆術語測試 — 基於 APHIA FAQ Q20",
        difficulty="adversarial",
    ),
    QualityTestCase(
        id="ADV-04",
        category="對抗性",
        question="我要bring my 狗 to Taiwan，需要什麼documents？",
        reference_answer="輸入犬隻至台灣需要：1. 晶片植入 2. 狂犬病不活化疫苗接種證明 3. 輸出國政府動物健康證明書正本 4. 輸入同意文件 5. 疫區國家另需 FAVN 抗體力價報告。（應能理解中英混用並正確回答）",
        source="中英混用提問測試 — 基於 APHIA FAQ Q7/Q23",
        difficulty="adversarial",
    ),
    QualityTestCase(
        id="ADV-05",
        category="對抗性",
        question="聽說隔離要 21 天？那太久了吧",
        reference_answer="隔離期並非 21 天。2024 年新制下，需隔離者為 7 天（非 21 天）。且符合條件者可申請免隔離。過去的規定已更新。",
        source="過時資訊測試 — 基於 APHIA FAQ Q31 及 2024 新制",
        difficulty="adversarial",
    ),
    QualityTestCase(
        id="ADV-06",
        category="對抗性",
        question="從日本來需要 180 天等待期嗎？",
        reference_answer="不需要。日本是狂犬病非疫區，不需要 FAVN 抗體檢測，也不需要 180 天等待期。但犬貓須在日本居住滿 180 天才能以非疫區身分輸入。",
        source="矛盾邏輯測試 — 基於 APHIA FAQ Q9 + 非疫區規定",
        difficulty="adversarial",
    ),
    QualityTestCase(
        id="ADV-07",
        category="對抗性",
        question="費用多少？要準備什麼文件？隔離多久？",
        reference_answer="須同時回答三個問題：1. 費用：機場檢疫資料鍵輸費 NT$100、FAVN 檢測（如需）NT$3,000-5,000、隔離費依場所而異、輸入同意文件免費。2. 文件：晶片、疫苗證明、健康證明書正本、輸入同意文件、疫區另需 FAVN 報告。3. 隔離：原則 7 天，符合條件可免隔離。",
        source="多重問題測試 — 綜合 APHIA FAQ",
        difficulty="adversarial",
    ),
    QualityTestCase(
        id="ADV-08",
        category="對抗性",
        question="我的狗被扣在機場了怎麼辦！好緊張！",
        reference_answer="犬貓留置機場可能原因：文件不齊、假日到達無法辦理、或等待送往隔離場所。建議立即聯繫檢疫機關：桃園機場 03-398-2663、高雄機場 07-972-0211、松山機場 02-8770-1535。假日無法辦理通關，須等下個上班日。",
        source="緊急情緒測試 — 基於 APHIA FAQ Q13/Q28 + 服務資訊",
        difficulty="adversarial",
    ),
    QualityTestCase(
        id="ADV-09",
        category="對抗性",
        question="從日本和從美國帶狗回來有什麼差別？",
        reference_answer="主要差別：日本為非疫區，不需 FAVN 抗體檢測、不需 180 天等待期、通常免隔離、準備期約 2-3 個月。美國本土為疫區，需 FAVN 檢測（≥0.5 IU/mL）、需等待 180 天（免隔離）或 90 天（隔離 7 天）、須用台灣格式健康證明經 USDA 背書、準備期約 7-8 個月。夏威夷和關島例外，適用非疫區規定。",
        source="比較題測試 — 基於 petq_faq.csv 日本/美國條目",
        difficulty="adversarial",
    ),
    QualityTestCase(
        id="ADV-10",
        category="對抗性",
        question="我的狗的 FAVN 報告顯示 0.48 IU/mL，差一點點，可以通融嗎？",
        reference_answer="不行，0.48 IU/mL 未達合格標準 0.5 IU/mL，無法通融。須補打狂犬病不活化疫苗（booster），等待至少 30 天後重新採血送驗。若來自疫區，180 天等待期需從新的採血日重新起算。不接受同一檢體複檢。",
        source="邊界值測試 — 基於 APHIA FAQ Q20/Q26 + petq_faq.csv 抗體力價不足",
        difficulty="adversarial",
    ),
    QualityTestCase(
        id="ADV-11",
        category="對抗性",
        question="我養的比特犬可以帶去台灣嗎？",
        reference_answer="不行。台灣自 2022 年 3 月 1 日起禁止飼養及輸入美國比特鬥牛犬（American Pit Bull Terrier）及美國史大佛夏牛頭犬（American Staffordshire Terrier）。違反者依《動物保護法》處罰。",
        source="禁止犬種測試 — 基於 petq_faq.csv 禁止輸入犬種",
        difficulty="adversarial",
    ),
    QualityTestCase(
        id="ADV-12",
        category="對抗性",
        question="週六到桃園機場可以辦犬貓入境嗎？",
        reference_answer="不行。假日、週末及國定假日無法辦理犬貓入境通關檢疫及押運作業。請安排在週一至週五上班日入境。假日抵達的犬貓會暫留機場，待下個上班日辦理，可能產生額外費用。",
        source="假日限制測試 — 基於 petq_faq.csv 假日入境規定",
        difficulty="adversarial",
    ),

    # =========================================================================
    # Source 4: 多語系測試
    # =========================================================================
    QualityTestCase(
        id="LANG-EN",
        category="多語系",
        question="I'm moving to Taiwan from the US with my Labrador. She's been vaccinated against rabies with an inactivated vaccine 6 months ago and has a FAVN titer of 0.7 IU/mL from Kansas State lab. The blood was drawn 4 months ago. What steps do I still need to complete before bringing her in?",
        reference_answer="Since the US mainland is a rabies-infected area, the dog needs: import permit (apply at least 20 days before, or 120 days for quarantine exemption), official health certificate from USDA-APHIS using Taiwan's format with original ink endorsement, issued within 10 days of departure. With FAVN ≥0.5 IU/mL and blood drawn 4 months ago: if applying 120+ days ahead with blood sampling 180 days to 1 year before entry, can be exempt from quarantine; otherwise 7-day quarantine applies since blood was drawn only 4 months ago (less than 180 days). Must also have ISO microchip.",
        source="English scenario — based on APHIA FAQ Q7/Q11/Q20 + petq_faq.csv US entry",
        difficulty="hard",
    ),
    QualityTestCase(
        id="LANG-VI",
        category="多語系",
        question="Tôi muốn mang chó từ Việt Nam sang Đài Loan. Tôi cần chuẩn bị những gì? Chi phí khoảng bao nhiêu?",
        reference_answer="越南為疫區，需要：ISO 晶片、狂犬病不活化疫苗、FAVN 抗體力價檢測（≥0.5 IU/mL）、180 天等待期（免隔離）或 90 天（隔離 7 天）、越南官方健康證明書、輸入同意文件。費用包括：FAVN 檢測約 NT$3,000-5,000、機場檢疫費 NT$100、隔離費依場所而異、航空運輸費。準備期約 7-8 個月。",
        source="Vietnamese — based on petq_faq.csv 東南亞條目",
        difficulty="hard",
    ),
    QualityTestCase(
        id="LANG-TH",
        category="多語系",
        question="ฉันจะพาแมวจากกรุงเทพไปไต้หวัน ต้องทำอย่างไรบ้าง? ต้องกักตัวกี่วัน?",
        reference_answer="泰國為疫區，需完整疫區流程：晶片、狂犬病不活化疫苗、FAVN 檢測（≥0.5 IU/mL）、等待期。隔離原則 7 天，符合 2024 年新制條件可免隔離。須上班日入境。",
        source="Thai — based on petq_faq.csv 東南亞條目",
        difficulty="hard",
    ),
    QualityTestCase(
        id="LANG-JA",
        category="多語系",
        question="日本から台湾に犬を連れて行きたいのですが、必要な書類と手続きを教えてください。検疫は必要ですか？",
        reference_answer="日本は非疫区のため、FAVN 抗體檢測不要、通常免隔離。須備：ISO 晶片、狂犬病不活化疫苗（出發前 30 天至 1 年）、日本農林水產省健康證明書、輸入同意文件（入境前 20 天申請）。犬貓須在日本居住滿 180 天。準備期約 2-3 個月。",
        source="Japanese — based on petq_faq.csv 日本條目",
        difficulty="hard",
    ),
    QualityTestCase(
        id="LANG-ID",
        category="多語系",
        question="Saya ingin membawa kucing saya dari Jakarta ke Taiwan. Apa saja persyaratannya? Berapa lama proses karantina?",
        reference_answer="印尼為疫區，需要：ISO 晶片、狂犬病不活化疫苗、FAVN 抗體力價檢測（≥0.5 IU/mL）、180 天等待期（免隔離）或 90 天（隔離 7 天）、印尼官方健康證明書、輸入同意文件。準備期約 7-8 個月。",
        source="Indonesian — based on petq_faq.csv 東南亞條目",
        difficulty="hard",
    ),
    QualityTestCase(
        id="LANG-KO",
        category="多語系",
        question="한국에서 대만으로 강아지를 데려가고 싶은데, 어떤 서류가 필요한가요? 격리 기간은 얼마나 되나요?",
        reference_answer="韓國為疫區，需要：ISO 晶片、狂犬病不活化疫苗、FAVN 抗體力價檢測（≥0.5 IU/mL）、180 天等待期（免隔離）或 90 天（隔離 7 天）、韓國官方健康證明書、輸入同意文件。隔離原則 7 天，符合新制條件可免。",
        source="Korean — based on petq_faq.csv 韓國條目",
        difficulty="hard",
    ),

    # =========================================================================
    # Source 5: 情境模擬 (基於官方 FAQ 延伸的複合情境)
    # =========================================================================
    QualityTestCase(
        id="SCEN-01",
        category="情境模擬",
        question="我住在美國加州，養了一隻柴犬，想帶回台灣定居。他已經打了狂犬病疫苗但好像是減毒活疫苗，這樣可以嗎？",
        reference_answer="不行。台灣僅接受不活化疫苗（killed/inactivated），不接受減毒活疫苗（modified live virus）。需重新施打不活化疫苗，等待至少 30 天後再做 FAVN 抗體檢測。美國本土為疫區，完整流程需 7-8 個月。",
        source="基於 APHIA FAQ Q33 + petq_faq.csv 美國條目",
        difficulty="hard",
    ),
    QualityTestCase(
        id="SCEN-02",
        category="情境模擬",
        question="我從英國帶貓回台灣，但飛機要在香港轉機，會影響嗎？",
        reference_answer="會有影響。英國為非疫區，但香港不在非疫區名單中（屬疫區）。經疫區轉機若無法提供未出港站且未接觸其他動物之證明文件，或輸出國檢疫機關封條，可能須隔離 7 天。建議選擇直飛或經其他非疫區國家轉機。",
        source="基於 APHIA FAQ Q15 + petq_faq.csv 轉機條目",
        difficulty="hard",
    ),
    QualityTestCase(
        id="SCEN-03",
        category="情境模擬",
        question="我的孟加拉貓（豹貓）F4 可以帶進台灣嗎？",
        reference_answer="F4（第 4 代混種）不行直接按一般犬貓輸入。豹貓須為 F5（第 5 代）或以上才視為家貓，適用犬貓輸入檢疫條件。F4 以下受野生動物保育法規範，須先經林務及自然保育署同意，且以學術研究機構等為限。",
        source="基於 petq_faq.csv 豹貓條目",
        difficulty="hard",
    ),
    QualityTestCase(
        id="SCEN-04",
        category="情境模擬",
        question="我的狗有癌症末期，不適合去隔離場所，可以在家隔離嗎？",
        reference_answer="可以申請居家隔離。非傳染性重大傷病（如癌末、癱瘓、重度心肺疾病、腎衰竭）不適宜至指定隔離場所者，可於輸入 30 日前申請，提供獸醫師病歷資料，居家隔離區域須為獨立空間。但須經專家專案評估，未通過仍需至指定場所隔離 7 天。",
        source="基於 petq_faq.csv 重大傷病居家隔離",
        difficulty="hard",
    ),
    QualityTestCase(
        id="SCEN-05",
        category="情境模擬",
        question="我有一隻導盲犬要帶去台灣出差，也需要隔離嗎？",
        reference_answer="導盲犬、導聾犬、肢體輔助犬、醫療服務犬等工作犬可免隔離檢疫。但仍須完成其他輸入檢疫程序（晶片、疫苗、健康證明、輸入同意文件等）。",
        source="基於 petq_faq.csv 工作犬免隔離",
        difficulty="normal",
    ),
    QualityTestCase(
        id="SCEN-06",
        category="情境模擬",
        question="我帶了一包美國的狗糧進台灣，需要申報嗎？",
        reference_answer="若狗糧含有偶蹄目（豬、牛、羊等）或禽鳥類（雞、鴨、鵝等）動物性成分，須向檢疫機關申報。未申報最高可罰新臺幣 100 萬元。僅含海鮮成分或經高溫滅菌罐製且不含牛源成分之產品則不需檢疫。建議主動向海關申報由檢疫人員判定。",
        source="基於 petq_faq.csv 犬貓食品規定",
        difficulty="normal",
    ),
    QualityTestCase(
        id="SCEN-07",
        category="情境模擬",
        question="2024 年新制的免隔離條件到底是什麼？我看不太懂",
        reference_answer="2024 年 2 月 29 日起實施的免隔離條件（擇一即可）：1. 於輸入 120 日前申請，且 FAVN 採血日在輸入前 180 天至 1 年內。2. 於輸入 20 日前申請，由輸出國檢疫機關直接將 RNATTD 聲明書 Email 至 rabiesreport@aphia.gov.tw。3. 於輸入 20 日前申請，由檢測實驗室直接將報告 Email 至 rabiesreport@aphia.gov.tw。不符合以上任一條件者仍須隔離 7 天。",
        source="基於 petq_faq.csv 2024 新制條目",
        difficulty="hard",
    ),
    QualityTestCase(
        id="SCEN-08",
        category="情境模擬",
        question="我的貓才 2 個月大，可以帶進台灣嗎？",
        reference_answer="可以輸入，但須隔離很長時間。未滿 90 日齡的幼貓輸入後須先隔離至滿 90 日齡，施打狂犬病疫苗後繼續隔離（疫區 180 天、非疫區 30 天）。建議等滿 90 日齡並完成所有檢疫程序後再輸入。",
        source="基於 APHIA FAQ Q22 + petq_faq.csv 幼齡犬貓",
        difficulty="normal",
    ),
    QualityTestCase(
        id="SCEN-09",
        category="情境模擬",
        question="從中國大陸帶狗來台灣跟從其他疫區有什麼不一樣？",
        reference_answer="從中國大陸輸入犬貓除適用一般疫區規定外，還須額外向經濟部國際貿易署申請專案進口許可。須同時持有國貿署許可文件和防檢署輸入同意文件，且犬貓僅能在國貿署許可的期間內輸入。但若是自台灣輸出至中國大陸再復運回台者，不需向國貿署申請。",
        source="基於 petq_faq.csv 中國大陸特別規定",
        difficulty="hard",
    ),
    QualityTestCase(
        id="SCEN-10",
        category="情境模擬",
        question="我的狗晶片是美國的 HomeAgain 品牌，不是 ISO 規格的，可以嗎？",
        reference_answer="台灣接受 ISO 11784/11785 規格及 AVID 9/10 晶片。若使用其他非標準晶片（如 HomeAgain 等），須自備相容的晶片讀取器隨身攜帶，以便檢疫人員確認晶片號碼。建議出發前確認晶片可正常讀取，且所有文件上的晶片號碼必須完全一致。",
        source="基於 petq_faq.csv 晶片規格 + APHIA FAQ Q17",
        difficulty="normal",
    ),
    QualityTestCase(
        id="SCEN-11",
        category="情境模擬",
        question="帶狗去日本要準備什麼？聽說日本很嚴格",
        reference_answer="帶犬貓至日本需要：1. ISO 晶片 2. 狂犬病不活化疫苗（2 次以上）3. 至 NVRI 做 FAVN 檢測（≥0.5 IU/mL，2024 年 10 月起日本僅接受 NVRI 報告）4. 等待 180 天 5. 出國前至防檢署分署辦理輸出檢疫。準備期約 8 個月以上。",
        source="基於 petq_faq.csv 輸出至日本",
        difficulty="hard",
    ),
    QualityTestCase(
        id="SCEN-12",
        category="情境模擬",
        question="請問防檢署和獸醫研究所的電話是多少？",
        reference_answer="防檢署：動物疫病諮詢專線 0800-761-590（免費）、本署 (02)2343-1401。桃園分署 03-398-2663、高雄機場檢疫站 07-972-0211。獸醫研究所：02-2621-2111 分機 555、狂犬病檢測信箱 rabies@mail.nvri.gov.tw。",
        source="基於 petq_faq.csv 服務資訊條目",
        difficulty="easy",
    ),
]


def summary():
    """Print test case summary statistics."""
    from collections import Counter
    cats = Counter(tc.category for tc in QUALITY_TEST_CASES)
    diffs = Counter(tc.difficulty for tc in QUALITY_TEST_CASES)
    print(f"Total test cases: {len(QUALITY_TEST_CASES)}")
    print(f"\nBy category:")
    for cat, count in cats.most_common():
        print(f"  {cat}: {count}")
    print(f"\nBy difficulty:")
    for diff, count in diffs.most_common():
        print(f"  {diff}: {count}")


if __name__ == "__main__":
    summary()
